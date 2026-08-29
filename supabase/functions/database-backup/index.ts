import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'
import * as XLSX from 'https://esm.sh/xlsx@0.18.5'
import { corsHeaders } from '../_shared/cors.ts'

// Version marker: v1.1.0-xlsx-backup

/**
 * DATABASE BACKUP EDGE FUNCTION (DPSjur)
 *
 * Purpose:
 * Automates daily periodic exports of the entire Supabase PostgreSQL database (public schema).
 * Saves dated structured JSON and SQL dump files to the 'backups' storage bucket.
 * Enforces a 7-day retention policy to avoid exceeding free-tier storage limits.
 * Logs execution metadata in public.backup_logs.
 *
 * Scheduling / Trigger mechanism:
 * - Can be invoked periodically (e.g., daily at 03:00 UTC) via external HTTP cron (Cron-Job.org, GitHub Actions, pg_cron/pg_net).
 * - Can be invoked manually via HTTP POST or GET by authorized admin users or service_role.
 *
 * Environment secrets used:
 * - SUPABASE_URL: URL of the Supabase project
 * - SUPABASE_SERVICE_ROLE_KEY: Key with administrative access to read tables and write to storage
 */

const BACKUP_BUCKET = 'backups'
const RETENTION_DAYS = 7

// List of public tables to backup in dependency/logical order
const TABLES_TO_BACKUP = [
  'profiles',
  'settings',
  'case_systems',
  'suppliers',
  'clients',
  'cases',
  'appointments',
  'tasks',
  'transactions',
  'transaction_cases',
  'petitions',
  'document_templates',
  'logs',
  'user_sessions',
  'whatsapp_messages',
]

// Main tables exported as separate sheets in the XLSX backup workbook
const EXCEL_SHEETS_CONFIG: { table: string; sheetName: string }[] = [
  { table: 'cases', sheetName: 'Processos' },
  { table: 'clients', sheetName: 'Clientes' },
  { table: 'transactions', sheetName: 'Transações Financeiras' },
  { table: 'tasks', sheetName: 'Tarefas' },
]

/**
 * Escapes a JS value for inclusion in PostgreSQL INSERT SQL statements.
 */
function escapeSqlValue(value: unknown): string {
  if (value === null || value === undefined) {
    return 'NULL'
  }
  if (typeof value === 'boolean') {
    return value ? 'TRUE' : 'FALSE'
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? String(value) : 'NULL'
  }
  if (typeof value === 'object') {
    // Array or JSON/JSONB
    const jsonStr = JSON.stringify(value).replace(/'/g, "''")
    return `'${jsonStr}'::jsonb`
  }
  // Strings and others
  const str = String(value).replace(/'/g, "''")
  return `'${str}'`
}

/**
 * Generates valid SQL INSERT statements for rows in a table.
 */
function generateTableSql(tableName: string, rows: Record<string, unknown>[]): string {
  if (!rows || rows.length === 0) {
    return `-- Table: public.${tableName} (0 rows)\n\n`
  }

  const columns = Object.keys(rows[0])
  const quotedColumns = columns.map((col) => `"${col}"`).join(', ')

  let sql = `-- Table: public.${tableName} (${rows.length} rows)\n`

  // Group into batches of 100 for efficient execution during restore
  const batchSize = 100
  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize)
    const valuesList = batch
      .map((row) => {
        const rowVals = columns.map((col) => escapeSqlValue(row[col]))
        return `(${rowVals.join(', ')})`
      })
      .join(',\n')

    sql += `INSERT INTO public."${tableName}" (${quotedColumns})\nVALUES\n${valuesList}\nON CONFLICT (id) DO UPDATE SET\n`
    const updates = columns
      .filter((col) => col !== 'id')
      .map((col) => `  "${col}" = EXCLUDED."${col}"`)
      .join(',\n')

    if (updates) {
      sql += `${updates};\n\n`
    } else {
      sql = sql.replace(
        /\nON CONFLICT \(id\) DO UPDATE SET\n$/,
        '\nON CONFLICT (id) DO NOTHING;\n\n',
      )
    }
  }

  return sql
}

/**
 * Normalizes table row values for clean Excel cells (objects/arrays formatted as JSON strings)
 */
function sanitizeRowsForExcel(rows: Record<string, unknown>[]): Record<string, unknown>[] {
  if (!rows || rows.length === 0) return []
  return rows.map((row) => {
    const cleanRow: Record<string, unknown> = {}
    for (const [key, val] of Object.entries(row)) {
      if (val === null || val === undefined) {
        cleanRow[key] = ''
      } else if (typeof val === 'object') {
        cleanRow[key] = JSON.stringify(val)
      } else {
        cleanRow[key] = val
      }
    }
    return cleanRow
  })
}

/**
 * Builds a multi-sheet XLSX buffer containing the principal system tables:
 * Processos, Clientes, Transações Financeiras e Tarefas.
 */
function generateExcelBackupBuffer(
  backupData: Record<string, Record<string, unknown>[]>,
): Uint8Array {
  const workbook = XLSX.utils.book_new()

  for (const { table, sheetName } of EXCEL_SHEETS_CONFIG) {
    const tableData = backupData[table] || []
    const sanitizedData = sanitizeRowsForExcel(tableData)
    const worksheet = XLSX.utils.json_to_sheet(sanitizedData)
    XLSX.utils.book_append_sheet(workbook, worksheet, sheetName)
  }

  const rawBuffer = XLSX.write(workbook, { type: 'array', bookType: 'xlsx' })
  return new Uint8Array(rawBuffer)
}

/**
 * Deletes backup files in storage that are older than RETENTION_DAYS.
 */
async function enforceRetentionPolicy(
  supabase: any,
): Promise<{ deleted: string[]; errors: string[] }> {
  const deleted: string[] = []
  const errors: string[] = []

  try {
    const { data: files, error } = await supabase.storage.from(BACKUP_BUCKET).list('', {
      limit: 100,
      sortBy: { column: 'created_at', order: 'asc' },
    })

    if (error) {
      errors.push(`Error listing backup files: ${error.message}`)
      return { deleted, errors }
    }

    if (!files || files.length === 0) {
      return { deleted, errors }
    }

    const cutoffDate = new Date()
    cutoffDate.setDate(cutoffDate.getDate() - RETENTION_DAYS)

    const filesToDelete: string[] = []

    for (const file of files) {
      if (file.name === '.emptyFolderPlaceholder') continue

      // Check creation/updated date or parse date from filename backup-YYYY-MM-DD
      let fileDate: Date | null = null
      if (file.created_at) {
        fileDate = new Date(file.created_at)
      } else {
        const dateMatch = file.name.match(/backup-(\d{4}-\d{2}-\d{2})/)
        if (dateMatch) {
          fileDate = new Date(dateMatch[1])
        }
      }

      if (fileDate && fileDate < cutoffDate) {
        filesToDelete.push(file.name)
      }
    }

    if (filesToDelete.length > 0) {
      console.log(`[RETENTION] Deleting ${filesToDelete.length} stale backup files:`, filesToDelete)
      const { error: delError } = await supabase.storage.from(BACKUP_BUCKET).remove(filesToDelete)
      if (delError) {
        errors.push(`Error deleting stale files: ${delError.message}`)
      } else {
        deleted.push(...filesToDelete)
      }
    }
  } catch (err: any) {
    errors.push(`Retention policy exception: ${err.message || String(err)}`)
  }

  return { deleted, errors }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const startTime = Date.now()

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error(
        'Supabase environment credentials (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY) are missing.',
      )
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false },
    })

    // Parse options from query parameters or JSON body
    let generateSql = true
    let generateJson = true
    let generateXlsx = true
    let triggerType = 'auto'

    if (req.method === 'POST') {
      try {
        const body = await req.json()
        if (body.generateSql !== undefined) generateSql = Boolean(body.generateSql)
        if (body.generateJson !== undefined) generateJson = Boolean(body.generateJson)
        if (body.generateXlsx !== undefined) generateXlsx = Boolean(body.generateXlsx)
        if (body.triggerType) triggerType = String(body.triggerType)
      } catch {
        // Body is optional or empty
      }
    } else {
      const url = new URL(req.url)
      if (url.searchParams.has('sql')) generateSql = url.searchParams.get('sql') === 'true'
      if (url.searchParams.has('json')) generateJson = url.searchParams.get('json') === 'true'
      if (url.searchParams.has('xlsx')) generateXlsx = url.searchParams.get('xlsx') === 'true'
      if (url.searchParams.has('trigger')) triggerType = url.searchParams.get('trigger') || 'manual'
    }

    const now = new Date()
    const dateStr = now.toISOString().split('T')[0] // YYYY-MM-DD
    const timestampStr = now.toISOString().replace(/[:.]/g, '-')
    const jsonFileName = `backup-${dateStr}-${timestampStr}.json`
    const sqlFileName = `backup-${dateStr}-${timestampStr}.sql`
    const xlsxFileName = `backup-${dateStr}-${timestampStr}.xlsx`

    console.log(`[BACKUP] Starting backup generation at ${now.toISOString()}...`)

    // 1. Fetch data from all tables
    const backupData: Record<string, Record<string, unknown>[]> = {}
    const recordCounts: Record<string, number> = {}
    let totalRecords = 0

    for (const table of TABLES_TO_BACKUP) {
      const { data, error } = await supabase.from(table).select('*')
      if (error) {
        console.warn(`[BACKUP] Warning: failed to fetch table ${table}: ${error.message}`)
        backupData[table] = []
        recordCounts[table] = 0
      } else {
        backupData[table] = data || []
        recordCounts[table] = (data || []).length
        totalRecords += (data || []).length
      }
    }

    const uploadedFiles: { fileName: string; format: string; sizeBytes: number }[] = []

    // 2. Generate and upload JSON structured backup
    if (generateJson) {
      const fullJsonPayload = {
        metadata: {
          version: '1.0',
          system: 'DPSjur',
          exported_at: now.toISOString(),
          tables_count: TABLES_TO_BACKUP.length,
          total_records: totalRecords,
          record_counts: recordCounts,
          retention_days: RETENTION_DAYS,
        },
        data: backupData,
      }

      const jsonString = JSON.stringify(fullJsonPayload, null, 2)
      const jsonBytes = new TextEncoder().encode(jsonString)

      const { error: jsonUploadErr } = await supabase.storage
        .from(BACKUP_BUCKET)
        .upload(jsonFileName, jsonBytes, {
          contentType: 'application/json',
          upsert: true,
        })

      if (jsonUploadErr) {
        throw new Error(`Failed to upload JSON backup to storage: ${jsonUploadErr.message}`)
      }

      uploadedFiles.push({
        fileName: jsonFileName,
        format: 'json',
        sizeBytes: jsonBytes.length,
      })

      // Log JSON backup
      await supabase.from('backup_logs').insert({
        file_name: jsonFileName,
        format: 'json',
        file_size_bytes: jsonBytes.length,
        tables_included: TABLES_TO_BACKUP,
        total_records: totalRecords,
        status: 'completed',
        trigger_type: triggerType,
      })
    }

    // 3. Generate and upload SQL dump backup
    if (generateSql) {
      let sqlContent = `-- ========================================================\n`
      sqlContent += `-- DPSjur Database Dump\n`
      sqlContent += `-- Generated: ${now.toISOString()}\n`
      sqlContent += `-- Total Records: ${totalRecords}\n`
      sqlContent += `-- ========================================================\n\n`
      sqlContent += `SET statement_timeout = 0;\n`
      sqlContent += `SET client_encoding = 'UTF8';\n`
      sqlContent += `SET standard_conforming_strings = on;\n\n`

      for (const table of TABLES_TO_BACKUP) {
        const rows = backupData[table] || []
        sqlContent += generateTableSql(table, rows)
      }

      const sqlBytes = new TextEncoder().encode(sqlContent)

      const { error: sqlUploadErr } = await supabase.storage
        .from(BACKUP_BUCKET)
        .upload(sqlFileName, sqlBytes, {
          contentType: 'application/sql',
          upsert: true,
        })

      if (sqlUploadErr) {
        console.warn(`[BACKUP] Warning: SQL dump upload failed: ${sqlUploadErr.message}`)
      } else {
        uploadedFiles.push({
          fileName: sqlFileName,
          format: 'sql',
          sizeBytes: sqlBytes.length,
        })

        // Log SQL backup
        await supabase.from('backup_logs').insert({
          file_name: sqlFileName,
          format: 'sql',
          file_size_bytes: sqlBytes.length,
          tables_included: TABLES_TO_BACKUP,
          total_records: totalRecords,
          status: 'completed',
          trigger_type: triggerType,
        })
      }
    }

    // 4. Generate and upload Excel (XLSX) multi-sheet backup
    if (generateXlsx) {
      try {
        const xlsxBytes = generateExcelBackupBuffer(backupData)
        const excelTables = EXCEL_SHEETS_CONFIG.map((c) => c.table)
        const excelTotalRecords = excelTables.reduce((acc, t) => acc + (recordCounts[t] || 0), 0)

        const { error: xlsxUploadErr } = await supabase.storage
          .from(BACKUP_BUCKET)
          .upload(xlsxFileName, xlsxBytes, {
            contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            upsert: true,
          })

        if (xlsxUploadErr) {
          console.warn(`[BACKUP] Warning: Excel (XLSX) upload failed: ${xlsxUploadErr.message}`)
        } else {
          uploadedFiles.push({
            fileName: xlsxFileName,
            format: 'xlsx',
            sizeBytes: xlsxBytes.length,
          })

          // Log Excel backup
          await supabase.from('backup_logs').insert({
            file_name: xlsxFileName,
            format: 'xlsx',
            file_size_bytes: xlsxBytes.length,
            tables_included: excelTables,
            total_records: excelTotalRecords,
            status: 'completed',
            trigger_type: triggerType,
          })
        }
      } catch (excelErr: any) {
        console.error('[BACKUP] Error generating Excel (XLSX) backup:', excelErr)
        await supabase.from('backup_logs').insert({
          file_name: xlsxFileName,
          format: 'xlsx',
          file_size_bytes: 0,
          tables_included: EXCEL_SHEETS_CONFIG.map((c) => c.table),
          total_records: 0,
          status: 'failed',
          error_message: excelErr?.message || String(excelErr),
          trigger_type: triggerType,
        })
      }
    }

    // 5. Enforce 7-day retention policy (clean up older files)
    const retentionResult = await enforceRetentionPolicy(supabase)

    const executionTimeMs = Date.now() - startTime

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Database backup completed successfully.',
        execution_time_ms: executionTimeMs,
        total_records: totalRecords,
        record_counts: recordCounts,
        uploaded_files: uploadedFiles,
        retention: {
          days: RETENTION_DAYS,
          deleted_stale_files: retentionResult.deleted,
          warnings: retentionResult.errors,
        },
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      },
    )
  } catch (err: any) {
    console.error('[BACKUP ERROR]', err)

    // Attempt to log error in backup_logs
    try {
      const supabaseUrl = Deno.env.get('SUPABASE_URL')
      const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
      if (supabaseUrl && supabaseServiceKey) {
        const supabase = createClient(supabaseUrl, supabaseServiceKey)
        await supabase.from('backup_logs').insert({
          file_name: 'failed_backup',
          format: 'unknown',
          file_size_bytes: 0,
          tables_included: TABLES_TO_BACKUP,
          total_records: 0,
          status: 'failed',
          error_message: err.message || String(err),
          trigger_type: 'auto',
        })
      }
    } catch {
      // Ignore logging failure
    }

    return new Response(
      JSON.stringify({
        success: false,
        error: err.message || 'Unknown backup error',
        execution_time_ms: Date.now() - startTime,
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      },
    )
  }
})
