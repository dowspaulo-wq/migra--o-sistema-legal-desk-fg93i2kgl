-- Update backups bucket allowed_mime_types to include XLSX spreadsheet format
UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
  'application/json',
  'application/sql',
  'text/plain',
  'text/x-sql',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel',
  'application/octet-stream'
]
WHERE id = 'backups';
