import fs from 'node:fs';

const content = fs.readFileSync('docs/vps/20-auditar-backup.sh', 'utf8');
const lines = content.split('\n');

console.log('Total lines:', lines.length);

// Find all lines containing "CONSOLIDAÇÃO DO VEREDITO"
lines.forEach((line, idx) => {
  if (line.includes('CONSOLIDAÇÃO DO VEREDITO')) {
    console.log(`Line ${idx + 1}: ${line}`);
  }
});
