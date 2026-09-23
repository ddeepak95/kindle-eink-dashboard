const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const html=fs.readFileSync('preview.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const quote={textContent:'',append(footer){this.footer=footer;}};
let requests=0,cacheReads=0;
const context=vm.createContext({
  document:{getElementById(){return quote;},createElement(){return {};}},
  location:{protocol:'file:'},
  localStorage:{getItem(){cacheReads++;return 'Old cached quote|Old author';},setItem(){}},
  fetch:async()=>{requests++;return {ok:true,text:async()=>'Remote quote|Remote author'};},
  Intl,Date
});
vm.runInContext(script.slice(0,script.indexOf('    if(new URLSearchParams')),context);
(async()=>{
  await vm.runInContext('refreshQuote()',context);
  assert.equal(requests,0);assert.equal(cacheReads,0);
  const source=fs.readFileSync('layout/quotes.txt','utf8').replace(/\r\n/g,'\n').trim()+'\n';
  assert.equal(vm.runInContext('bundledQuotes',context),source);
  assert.ok(source.split('\n').some(line=>line.split('|')[0]===quote.textContent.slice(1,-1)));
  context.location.protocol='https:';
  await vm.runInContext('refreshQuote()',context);
  assert.equal(requests,1);
  assert.equal(quote.textContent,'\u201cRemote quote\u201d');
  console.log('PASS local preview uses current bundled quotes, ignores stale cache, and hosted preview still fetches GitHub.');
})().catch(error=>{console.error(error);process.exitCode=1;});