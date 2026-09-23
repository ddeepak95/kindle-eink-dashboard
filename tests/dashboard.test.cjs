const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
const html = fs.readFileSync('preview.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements = new Map();
const document = {
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, {textContent:'', append(child){this.footer=child;}});
    return elements.get(id);
  },
  createElement(){return {};}
};
const context = vm.createContext({document, Intl, Date});
vm.runInContext(script.slice(0,script.indexOf('    if(new URLSearchParams')), context);
const common = fs.readFileSync('bin/common.sh','utf8');
const functions = common.slice(common.indexOf('# Rotate a quote list'));
const bash = process.env.BASH_PATH || (process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash');
function shell(input) {
  const result = spawnSync(bash, ['-s'], {input,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  return result.stdout.trim();
}
function check(name,temps,codes,rains,expected) {
  const hourly = {
    time:temps.map((_,i)=>new Date(Date.UTC(2026,8,22,13+i)).toISOString().slice(0,16)),
    temperature_2m:temps,weather_code:codes,precipitation_probability:rains
  };
  // A deliberately different current hour must never appear in the forecast.
  hourly.time.unshift('2026-09-22T12:00');
  hourly.temperature_2m=[99,...temps];
  hourly.weather_code=[95,...codes];
  hourly.precipitation_probability=[100,...rains];
  context.hourly=hourly;
  const groups=JSON.parse(vm.runInContext('JSON.stringify(groupHours(hourly))',context));
  assert.equal(groups.length,expected,name);
  assert.equal(groups[0].start,'2026-09-22T13:00',name+' starts next hour');
  if(temps.length>=12) assert.equal(groups.at(-1).end,'2026-09-23T00:00',name+' includes the twelfth future hour');
  const fixture=hourly.time.map((t,i)=>[t,hourly.temperature_2m[i],hourly.weather_code[i],hourly.precipitation_probability[i]].join('|')).join('\n');
  const actual=shell(functions+'\n'+[
    'HOURLY_FORECAST_COUNT=12',
    'hourly_array_value() {',
    'case "$1" in time) column=1;; temperature_2m) column=2;; weather_code) column=3;; precipitation_probability) column=4;; esac',
    'printf \'%s\\n\' \''+fixture+'\' | awk -F \'|\' -v n="$2" -v c="$column" \'NR==n {print $c}\'',
    '}',
    'forecast_groups'
  ].join('\n'));
  const expectedLines=groups.map(g=>[g.start,g.end,Math.round(g.min),Math.round(g.max),g.code,g.rain].join('|')).join('\n');
  assert.equal(actual,expectedLines,name+' shell/preview parity');
  console.log('PASS',name);
}
check('stable four-hour period',[70,71,72,71],[2,2,2,2],[10,10,15,10],1);
check('cumulative temperature drift',[70,73,74],[2,2,2],[10,10,10],2);
check('rain starts, intensifies, stops',[70,70,70,70],[2,61,65,2],[10,70,80,10],4);
check('precipitation threshold',[70,70],[3,3],[40,50],2);
check('precipitation probability jump',[70,70],[61,61],[50,80],2);
check('clear and mostly clear',[70,71],[0,1],[0,0],1);
check('missing data leaves gap',[70,null,70],[2,2,2],[0,0,0],2);
check('six distinct periods',[70,73,76,79,82,85],[0,2,3,61,71,95],[0,0,10,70,80,90],6);
assert.equal(vm.runInContext("periodLabel('2026-09-22T13:00','2026-09-22T16:00')",context),'1\u20134 PM');
assert.equal(vm.runInContext("periodLabel('2026-09-22T23:00','2026-09-23T01:00')",context),'11 PM\u20131 AM');
vm.runInContext("showQuote('Only quote|Author\\n')",context);
assert.equal(elements.get('quote').textContent,'\u201cOnly quote\u201d');
assert.equal(elements.get('quote').footer.textContent,'\u2014 Author');
assert.throws(()=>vm.runInContext("showQuote('invalid')",context));
const quote=shell(functions+"\nselect_quote data/quotes.txt\n");
assert.equal(quote.split('\n').length,2);
assert.ok(!quote.includes('|'));
console.log('PASS time labels, quote parsing, and shell quote selection');
check('three-degree variation merges',[70,73,71],[2,2,2],[10,10,10],1);
check('12 stable hours merge',Array(12).fill(70),Array(12).fill(2),Array(12).fill(10),1);
check('all 12 changing hours retained',Array.from({length:12},(_,i)=>60+i*4),Array(12).fill(2),Array(12).fill(10),12);
check('rain in hour 12 retained',Array(12).fill(70),[...Array(11).fill(2),61],[...Array(11).fill(10),80],2);
check('future window stops after 12 hours',Array.from({length:13},(_,i)=>60+i*4),Array(13).fill(2),Array(13).fill(10),12);
assert.ok(html.includes('forecast_hours=13'), 'preview requests current plus 12 future hours');
assert.ok(fs.readFileSync('bin/fetch.sh','utf8').includes('forecast_hours=$((HOURLY_FORECAST_COUNT + 1))'), 'Kindle requests one extra hour');