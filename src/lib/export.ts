export function downloadCSV(data: any[], filename: string) {
  if (!data || data.length === 0) return

  const headers = Array.from(
    new Set(data.reduce((acc, row) => acc.concat(Object.keys(row)), [] as string[])),
  )

  const csvRows = []
  csvRows.push(headers.join(','))

  for (const row of data) {
    const values = headers.map((header) => {
      const val = row[header]
      if (val === null || val === undefined) return '""'
      const escaped = ('' + val).replace(/"/g, '""')
      return `"${escaped}"`
    })
    csvRows.push(values.join(','))
  }

  const blob = new Blob(['\uFEFF' + csvRows.join('\n')], { type: 'text/csv;charset=utf-8;' })
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.setAttribute('download', filename)
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
}
