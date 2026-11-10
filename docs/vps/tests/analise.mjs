import fs from 'node:fs';

const content = fs.readFileSync('docs/vps/20-auditar-backup.sh', 'utf8');
const lines = content.split('\n');

// Procurar índices onde aparece CONSOLIDAÇÃO DO VEREDITO
// e onde termina o script (exit "${EXIT_OK}" etc.)
let consIdx = -1;
let lastExitIdx = -1;

for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes('CONSOLIDAÇÃO DO VEREDITO')) {
    consIdx = i;
  }
  if (lines[i].includes('exit "${EXIT_STRUCTURE_FAIL}"')) {
    lastExitIdx = i;
  }
}

console.log('consIdx:', consIdx, 'lastExitIdx:', lastExitIdx);

// Vamos ver os marcadores ======= entre consIdx e o final
const markers = [];
for (let i = consIdx; i < lines.length; i++) {
  if (lines[i].startsWith('=======')) {
    markers.push(i + 1); // 1-based
  }
}
console.log('Marcadores ======= encontrados nas linhas:', markers);
