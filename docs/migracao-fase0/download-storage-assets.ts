import fs from 'node:fs'
import path from 'node:path'
import https from 'node:https'

// Script auxiliar para download em lote de todos os objetos públicos de storage
const manifestPath = path.resolve('docs/migracao-fase0/04-storage-manifest.json')
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'))

const outputDir = path.resolve('docs/migracao-fase0/storage-copies')

async function downloadFile(url: string, dest: string): Promise<void> {
  const dir = path.dirname(dest)
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true })
  }

  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(`Failed to download ${url}: status ${res.statusCode}`))
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
  console.log(`Iniciando download de ${manifest.length} objetos...`)
  let downloaded = 0
  for (const item of manifest) {
    if (item.bucket_id === 'backups') {
      console.log(`[PULAR] Bucket privado de backups: ${item.name}`)
      continue
    }
    const dest = path.join(outputDir, item.bucket_id, item.name)
    try {
      await downloadFile(item.public_url, dest)
      downloaded++
      console.log(`[OK] Baixado: ${item.bucket_id}/${item.name}`)
    } catch (e: any) {
      console.error(`[FALHA] ${item.bucket_id}/${item.name}: ${e.message}`)
    }
  }
  console.log(`Concluído. Total baixado: ${downloaded}`)
}

if (process.argv[1] && process.argv[1].endsWith('download-storage-assets.ts')) {
  main()
}
