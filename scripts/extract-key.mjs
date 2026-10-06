async function main() {
  const urls = [
    'https://dpsadvocacia.goskip.app/',
    'https://migracao-sistema-legal-desk-8976b--preview.goskip.app/',
    'https://migracao-sistema-legal-desk-8976b.goskip.app/',
  ]

  const results = {}

  for (const pageUrl of urls) {
    try {
      console.log(`Fetching page: ${pageUrl}`)
      const res = await fetch(pageUrl)
      const html = await res.text()
      console.log(`Page status: ${res.status}, length: ${html.length}`)

      // Find scripts
      const scriptMatches = [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)].map(
        (m) => m[1],
      )
      console.log(`Scripts found on ${pageUrl}:`, scriptMatches)

      for (const scriptPath of scriptMatches) {
        const fullScriptUrl = new URL(scriptPath, pageUrl).href
        console.log(`Fetching script: ${fullScriptUrl}`)
        const sRes = await fetch(fullScriptUrl)
        const scriptCode = await sRes.text()
        console.log(`Script ${fullScriptUrl} status: ${sRes.status}, length: ${scriptCode.length}`)

        // Find sb_publishable keys
        const sbMatches = [...scriptCode.matchAll(/sb_publishable_[A-Za-z0-9_-]+/g)].map(
          (m) => m[0],
        )
        // Find JWT tokens (anon keys)
        const jwtMatches = [
          ...scriptCode.matchAll(/eyJhbGciOi[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g),
        ].map((m) => m[0])
        // Find supabase URLs
        const urlMatches = [...scriptCode.matchAll(/https:\/\/[a-z0-9-]+\.supabase\.co/g)].map(
          (m) => m[0],
        )

        results[fullScriptUrl] = {
          sbMatches: [...new Set(sbMatches)],
          jwtMatches: [...new Set(jwtMatches)],
          urlMatches: [...new Set(urlMatches)],
        }
      }
    } catch (err) {
      console.error(`Error processing ${pageUrl}:`, err)
    }
  }

  console.log('=== EXTRACTION RESULTS ===')
  console.log(JSON.stringify(results, null, 2))

  // Collect all unique keys
  const allSbKeys = new Set()
  const allJwtKeys = new Set()
  for (const info of Object.values(results)) {
    info.sbMatches.forEach((k) => allSbKeys.add(k))
    info.jwtMatches.forEach((k) => allJwtKeys.add(k))
  }

  console.log('Unique sb_publishable keys:', [...allSbKeys])
  console.log('Unique JWT keys:', [...allJwtKeys])

  const testKeyAgainst = async (projectRef, key) => {
    try {
      const resp = await fetch(
        `https://${projectRef}.supabase.co/auth/v1/token?grant_type=password`,
        {
          method: 'POST',
          headers: {
            apikey: key,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ email: 'teste@validacao.invalida', password: 'x' }),
        },
      )
      const data = await resp.text()
      return { status: resp.status, body: data }
    } catch (e) {
      return { error: String(e) }
    }
  }

  const validationResults = {}

  for (const key of [...allSbKeys, ...allJwtKeys]) {
    validationResults[`dagtlwojkqyivnjgveda_${key.slice(0, 20)}...`] = await testKeyAgainst(
      'dagtlwojkqyivnjgveda',
      key,
    )
    validationResults[`cpcafthwnqazopqftemj_${key.slice(0, 20)}...`] = await testKeyAgainst(
      'cpcafthwnqazopqftemj',
      key,
    )
  }

  // Also test the key Douglas previously used
  validationResults['dagtlwojkqyivnjgveda_douglas_key'] = await testKeyAgainst(
    'dagtlwojkqyivnjgveda',
    'sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_mNwxBRwO',
  )
  validationResults['cpcafthwnqazopqftemj_douglas_key'] = await testKeyAgainst(
    'cpcafthwnqazopqftemj',
    'sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_mNwxBRwO',
  )

  console.log('=== VALIDATION RESULTS ===')
  console.log(JSON.stringify(validationResults, null, 2))

  // Throw error with full summary so QA pipeline displays it
  throw new Error('KEY_EXTRACT_RESULT: ' + JSON.stringify({ results, validationResults }, null, 2))
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
