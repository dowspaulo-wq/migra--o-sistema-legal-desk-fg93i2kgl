import fs from 'node:fs'
import path from 'node:path'
import https from 'node:https'

/**
 * Script utilitário para sincronizar todos os 32 arquivos essenciais
 * de storage do SBJur para o VPS local / disco / bucket Supabase local.
 */

interface StorageItem {
  bucket_id: string
  name: string
  bytes: number
  mime_type: string
  public_url: string
  description?: string
}

const STORAGE_MANIFEST: StorageItem[] = [
  // Avatars (12)
  {
    bucket_id: 'avatars',
    name: '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf-0.25634000655999467.jpeg',
    bytes: 5865,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf-0.25634000655999467.jpeg',
    description: 'Avatar Guilherme Almeida',
  },
  {
    bucket_id: 'avatars',
    name: '4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf-0.34684794134325625.jpg',
    bytes: 497677,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/4ad65234-19ac-4b8d-aec5-fb0ad9ffdeaf-0.34684794134325625.jpg',
  },
  {
    bucket_id: 'avatars',
    name: '6501af65-cd6c-43c3-958a-3091ce93ba78-0.2806617070811477.jpg',
    bytes: 89039,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/6501af65-cd6c-43c3-958a-3091ce93ba78-0.2806617070811477.jpg',
  },
  {
    bucket_id: 'avatars',
    name: '6501af65-cd6c-43c3-958a-3091ce93ba78-0.3970545073819589.jpg',
    bytes: 3311432,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/6501af65-cd6c-43c3-958a-3091ce93ba78-0.3970545073819589.jpg',
    description: 'Avatar Douglas Atual',
  },
  {
    bucket_id: 'avatars',
    name: '8914e17d-64ce-4acc-88ab-5fc04f11ac24-0.6034897410318099.png',
    bytes: 1790978,
    mime_type: 'image/png',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/8914e17d-64ce-4acc-88ab-5fc04f11ac24-0.6034897410318099.png',
  },
  {
    bucket_id: 'avatars',
    name: '97971288-d3cf-4d66-a48f-8691ab0b40a4-0.009296859819198255.jpeg',
    bytes: 107977,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/97971288-d3cf-4d66-a48f-8691ab0b40a4-0.009296859819198255.jpeg',
  },
  {
    bucket_id: 'avatars',
    name: '97971288-d3cf-4d66-a48f-8691ab0b40a4-0.15838918068529484.png',
    bytes: 528619,
    mime_type: 'image/png',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/97971288-d3cf-4d66-a48f-8691ab0b40a4-0.15838918068529484.png',
  },
  {
    bucket_id: 'avatars',
    name: 'b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.07716052849733024.jpeg',
    bytes: 49390,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.07716052849733024.jpeg',
  },
  {
    bucket_id: 'avatars',
    name: 'b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.25608810045272723.jpeg',
    bytes: 51944,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.25608810045272723.jpeg',
  },
  {
    bucket_id: 'avatars',
    name: 'b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.4782258744095581.jpeg',
    bytes: 124521,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.4782258744095581.jpeg',
  },
  {
    bucket_id: 'avatars',
    name: 'b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.5471863503630024.jpeg',
    bytes: 51944,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.5471863503630024.jpeg',
  },
  {
    bucket_id: 'avatars',
    name: 'b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.7322693909650941.jpeg',
    bytes: 43847,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/avatars/b700846f-fc9e-4f3c-a48e-86a8e5e83f12-0.7322693909650941.jpeg',
  },

  // Case systems icons (8)
  {
    bucket_id: 'case-systems',
    name: '0.1710385136882614.bmp',
    bytes: 12626,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.1710385136882614.bmp',
  },
  {
    bucket_id: 'case-systems',
    name: '0.38107057149783896.bmp',
    bytes: 109810,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.38107057149783896.bmp',
  },
  {
    bucket_id: 'case-systems',
    name: '0.584555652725446.bmp',
    bytes: 88379,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.584555652725446.bmp',
  },
  {
    bucket_id: 'case-systems',
    name: '0.7340156072577102.bmp',
    bytes: 42394,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.7340156072577102.bmp',
  },
  {
    bucket_id: 'case-systems',
    name: '0.7792231130266362.bmp',
    bytes: 25976,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.7792231130266362.bmp',
  },
  {
    bucket_id: 'case-systems',
    name: '0.8777420576239596.bmp',
    bytes: 31372,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.8777420576239596.bmp',
  },
  {
    bucket_id: 'case-systems',
    name: '0.9744052893612097.bmp',
    bytes: 21192,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.9744052893612097.bmp',
  },
  {
    bucket_id: 'case-systems',
    name: '0.9756833351919669.bmp',
    bytes: 156542,
    mime_type: 'image/bmp',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/case-systems/0.9756833351919669.bmp',
  },

  // Document templates (1)
  {
    bucket_id: 'document_templates',
    name: '1783792994284_Contrato prestacao de servicos INDENIZATORIA 2025.08.08.docx',
    bytes: 853396,
    mime_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/document_templates/1783792994284_Contrato%20prestacao%20de%20servicos%20INDENIZATORIA%202025.08.08.docx',
  },

  // Signature documents (5)
  {
    bucket_id: 'signature_documents',
    name: 'contrato_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785849055679.html',
    bytes: 599,
    mime_type: 'text/html',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_documents/contrato_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785849055679.html',
  },
  {
    bucket_id: 'signature_documents',
    name: 'hipossuficiencia_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785840293465.html',
    bytes: 718,
    mime_type: 'text/html',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_documents/hipossuficiencia_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785840293465.html',
  },
  {
    bucket_id: 'signature_documents',
    name: 'procuracao_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785838666890.html',
    bytes: 749,
    mime_type: 'text/html',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_documents/procuracao_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785838666890.html',
  },
  {
    bucket_id: 'signature_documents',
    name: 'procuracao_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785840257582.html',
    bytes: 749,
    mime_type: 'text/html',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_documents/procuracao_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785840257582.html',
  },
  {
    bucket_id: 'signature_documents',
    name: 'procuracao_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785840284785.html',
    bytes: 749,
    mime_type: 'text/html',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_documents/procuracao_3c8a2a60-50a2-44b4-9307-318b7516e0aa_1785840284785.html',
  },

  // Signature drawings (1)
  {
    bucket_id: 'signature_drawings',
    name: 'signature_99ff00af-2b93-4ca0-9714-20e2c3b20d5e_1785852915793.png',
    bytes: 9238,
    mime_type: 'image/png',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_drawings/signature_99ff00af-2b93-4ca0-9714-20e2c3b20d5e_1785852915793.png',
  },

  // Signature photos (3)
  {
    bucket_id: 'signature_photos',
    name: '05dd2890-4e2d-44d1-b63f-677e61ada290/selfie.jpg',
    bytes: 0,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_photos/05dd2890-4e2d-44d1-b63f-677e61ada290/selfie.jpg',
  },
  {
    bucket_id: 'signature_photos',
    name: '91710e61-5dd4-4cf3-81b9-7029e19fa312/selfie.jpg',
    bytes: 26990,
    mime_type: 'image/jpeg',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_photos/91710e61-5dd4-4cf3-81b9-7029e19fa312/selfie.jpg',
  },
  {
    bucket_id: 'signature_photos',
    name: 'selfie_99ff00af-2b93-4ca0-9714-20e2c3b20d5e_1785852915793.png',
    bytes: 472803,
    mime_type: 'image/png',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signature_photos/selfie_99ff00af-2b93-4ca0-9714-20e2c3b20d5e_1785852915793.png',
  },

  // Signed documents (2)
  {
    bucket_id: 'signed_documents',
    name: '05dd2890-4e2d-44d1-b63f-677e61ada290/procuracao.html',
    bytes: 1606,
    mime_type: 'text/html',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signed_documents/05dd2890-4e2d-44d1-b63f-677e61ada290/procuracao.html',
  },
  {
    bucket_id: 'signed_documents',
    name: '91710e61-5dd4-4cf3-81b9-7029e19fa312/hipossuficiencia.html',
    bytes: 1446,
    mime_type: 'text/html',
    public_url:
      'https://cpcafthwnqazopqftemj.supabase.co/storage/v1/object/public/signed_documents/91710e61-5dd4-4cf3-81b9-7029e19fa312/hipossuficiencia.html',
  },
]

async function downloadFile(url: string, dest: string): Promise<void> {
  const dir = path.dirname(dest)
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true })
  }

  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(`Status HTTP ${res.statusCode}`))
          return
        }
        const fileStream = fs.createWriteStream(dest)
        res.pipe(fileStream)
        fileStream.on('finish', () => {
          fileStream.close()
          resolve()
        })
        fileStream.on('error', reject)
      })
      .on('error', reject)
  })
}

async function main() {
  const targetDir = process.argv[2] || path.resolve('storage-sync')
  console.log(`Iniciando download de ${STORAGE_MANIFEST.length} arquivos para: ${targetDir}`)

  let successCount = 0
  for (const item of STORAGE_MANIFEST) {
    const dest = path.join(targetDir, item.bucket_id, item.name)
    try {
      await downloadFile(item.public_url, dest)
      successCount++
      console.log(`[OK] Baixado: ${item.bucket_id}/${item.name}`)
    } catch (e: any) {
      console.error(`[AVISO] Falha em ${item.bucket_id}/${item.name}: ${e.message}`)
    }
  }

  console.log(
    `\nSincronização concluída! Arquivos baixados: ${successCount} / ${STORAGE_MANIFEST.length}`,
  )
}

if (process.argv[1] && process.argv[1].endsWith('06-sync-storage-assets.ts')) {
  main()
}
