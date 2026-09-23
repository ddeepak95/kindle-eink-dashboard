const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const quotes=fs.readFileSync(path.join(root,'layout/quotes.txt'),'utf8').replace(/\r\n/g,'\n').trim()+'\n';
const lines=quotes.trim().split('\n');
if(lines.some(line=>line.split('|').length!==2||line.split('|').some(part=>!part.trim()))) throw Error('Expected Quote text|Author on every line');
const previewPath=path.join(root,'preview.html');
const preview=fs.readFileSync(previewPath,'utf8');
const pattern=/    \/\/ BEGIN BUNDLED QUOTES[\s\S]*?    \/\/ END BUNDLED QUOTES/;
if(!pattern.test(preview)) throw Error('Preview quote markers missing');
const encoded=JSON.stringify(quotes).replace(/</g,'\\u003c');
fs.writeFileSync(previewPath,preview.replace(pattern,()=>[
  '    // BEGIN BUNDLED QUOTES',
  '    const bundledQuotes='+encoded+';',
  '    // END BUNDLED QUOTES'
].join('\n')));
fs.writeFileSync(path.join(root,'data/quotes.txt'),quotes);
console.log('Synced '+lines.length+' quotes to the GitHub feed and local preview.');