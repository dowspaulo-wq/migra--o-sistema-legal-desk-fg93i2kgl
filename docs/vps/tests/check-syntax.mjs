import { readFileSync } from 'fs';

function checkBashSyntax(path) {
  const content = readFileSync(path, 'utf8');
  const lines = content.split('\n');
  const errors = [];

  let inHeredoc = false;
  let heredocDelimiter = '';
  let heredocStart = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    if (inHeredoc) {
      if (line.trim() === heredocDelimiter) {
        inHeredoc = false;
        heredocDelimiter = '';
      }
      continue;
    }

    // Check for heredoc start: <<'EOF', <<EOF, <<\EOF, << "EOF"
    const heredocMatch = line.match(/<<\s*['"]?([A-Za-z0-9_-]+)['"]?/);
    if (heredocMatch && !line.includes('<<-')) {
      inHeredoc = true;
      heredocDelimiter = heredocMatch[1];
      heredocStart = lineNum;
    }

    // Check git conflict markers
    if (line.startsWith('<<<<<<<') || line.startsWith('=======') || line.startsWith('>>>>>>>')) {
      errors.push(`Line ${lineNum}: Git conflict marker found: "${line}"`);
    }
  }

  if (inHeredoc) {
    errors.push(`Unclosed heredoc starting at line ${heredocStart} (delimiter: ${heredocDelimiter})`);
  }

  return errors;
}

for (const f of ['docs/vps/20-auditar-backup.sh', 'docs/vps/21-gerar-inventario.sh']) {
  const errs = checkBashSyntax(f);
  console.log(`${f}: ${errs.length === 0 ? 'NO CONFLICT MARKERS' : errs.join(', ')}`);
}
