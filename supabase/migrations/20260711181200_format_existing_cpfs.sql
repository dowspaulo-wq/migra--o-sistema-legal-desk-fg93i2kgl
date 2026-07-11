UPDATE public.clients
SET document = CONCAT(
  SUBSTRING(document FROM 1 FOR 3), '.',
  SUBSTRING(document FROM 4 FOR 3), '.',
  SUBSTRING(document FROM 7 FOR 3), '-',
  SUBSTRING(document FROM 10 FOR 2)
)
WHERE document IS NOT NULL
  AND LENGTH(document) = 11
  AND document ~ '^[0-9]{11}$';
