const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const crypto=require('node:crypto'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'dashboard-updates-'));
const bash=process.env.BASH_PATH||(process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'bash');
const shellPath=p=>p.replace(/\\/g,'/').replace(/^([A-Za-z]):/,(_,d)=>'/'+d.toLowerCase());
const quote=s=>"'"+s.replace(/'/g,"'\\''")+"'";
function release(n,render) {
  const dir=path.join(tmp,'remote/releases',String(n));
  fs.cpSync(path.join(root,'updates/releases/1'),dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'render.sh'),render);
  const files=fs.readFileSync(path.join(dir,'manifest.sha256'),'utf8').trim().split('\n').map(l=>l.split('  ')[1]);
  fs.writeFileSync(path.join(dir,'manifest.sha256'),files.map(f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(dir,f))).digest('hex')+'  '+f+'\n').join(''));
}
try {
  for (const n of [1,2,3]) release(n,'#!/bin/sh\ntrue\n');
  release(4,'#!/bin/sh\nif broken\n');
  const input=[
    'set -e',
    'ROOT='+quote(shellPath(root)),
    'TEST_ROOT='+quote(shellPath(tmp)),
    'CACHE_DIR="$TEST_ROOT/cache"; SCRIPT_DIR="$ROOT/bin"; EXTENSION_DIR="$ROOT"',
    'NETWORK_TIMEOUT_SECONDS=1; AUTO_UPDATE_LAYOUT=1; LAYOUT_UPDATE_URL=https://example.test/updates',
    'log_message() { printf "%s\\n" "$*"; }',
    '. "$ROOT/bin/updates.sh"',
    'curl() {',
    '  [ ! -f "$TEST_ROOT/offline" ] || return 1',
    '  while [ "$#" -gt 0 ]; do case "$1" in https://*) url="$1";; -o) shift; output="$1";; esac; shift; done',
    '  cp "$TEST_ROOT/remote/${url#https://example.test/updates/}" "$output"',
    '}',
    'run_layout() { printf "%s\\n" "$1" >> "$TEST_ROOT/rendered"; [ ! -f "$1/fail" ]; }',
    'mkdir "$UPDATE_DIR/check.lock"; printf "99999999\n" > "$UPDATE_DIR/check.lock/pid"',
    'printf "1\n" > "$TEST_ROOT/remote/latest.txt"',
    'check_layout_update',
    '[ "$(read_version pending)" = 1 ]; [ ! -f "$UPDATE_DIR/active" ]',
    '(render_with_updates)',
    '[ "$(read_version active)" = 1 ]; [ ! -f "$UPDATE_DIR/pending" ]',
    'check_layout_update; [ ! -f "$UPDATE_DIR/pending" ]',
    'touch "$TEST_ROOT/offline"; check_layout_update; [ "$(read_version active)" = 1 ]; rm "$TEST_ROOT/offline"',
    'printf "2\\n" > "$TEST_ROOT/remote/latest.txt"; check_layout_update',
    'touch "$UPDATE_DIR/2/fail"; (render_with_updates)',
    '[ "$(read_version active)" = 1 ]; [ "$(read_version rejected)" = 2 ]',
    'check_layout_update; [ ! -f "$UPDATE_DIR/pending" ]',
    'printf "3\\n" > "$TEST_ROOT/remote/latest.txt"; check_layout_update; (render_with_updates)',
    '[ "$(read_version active)" = 3 ]; [ "$(read_version previous)" = 1 ]',
    'touch "$UPDATE_DIR/3/fail"; (render_with_updates)',
    '[ "$(read_version active)" = 1 ]',
    'printf "4\\n" > "$TEST_ROOT/remote/latest.txt"; check_layout_update; [ ! -f "$UPDATE_DIR/pending" ]',
    'printf "tampered" >> "$TEST_ROOT/remote/releases/4/quotes.txt"',
    'check_layout_update; [ "$(read_version active)" = 1 ]; [ ! -f "$UPDATE_DIR/pending" ]',
    'printf "../escape\\n" > "$TEST_ROOT/remote/latest.txt"; check_layout_update; [ ! -f "$UPDATE_DIR/pending" ]',
    'AUTO_UPDATE_LAYOUT=0; (render_with_updates)',
    '[ "$(tail -n 1 "$TEST_ROOT/rendered")" = "$ROOT/layout" ]',
    'printf "PASS activation, unchanged version, offline, failed render, previous-version rollback, syntax, checksum, version validation, disabled updates\\n"'
  ].join('\n');
  const result=spawnSync(bash,['-s'],{input,encoding:'utf8',timeout:60000});
  process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
  assert.equal(result.status,0,result.error?.message||'Update integration tests failed');
  // The actual worker must surface drawing failures rather than its final log masking them.
  fs.mkdirSync(path.join(tmp,'bin'));fs.mkdirSync(path.join(tmp,'layout'));
  fs.copyFileSync(path.join(root,'bin/render-layout.sh'),path.join(tmp,'bin/render-layout.sh'));
  fs.writeFileSync(path.join(tmp,'weather.json'),'{}');
  fs.writeFileSync(path.join(tmp,'bin/common.sh'),'WEATHER_CACHE='+quote(shellPath(path.join(tmp,'weather.json')))+'\nfind_fbink() { echo true; }\nset_landscape() { return 0; }\n');
  fs.writeFileSync(path.join(tmp,'layout/render.sh'),'draw() { false; echo masked; }\ndraw\necho success\n');
  const worker=spawnSync(bash,[shellPath(path.join(tmp,'bin/render-layout.sh')),shellPath(path.join(tmp,'layout'))],{encoding:'utf8'});
  assert.notEqual(worker.status,0);assert.equal(worker.stdout,'');
  console.log('PASS rendering errors reach rollback controller');
  fs.writeFileSync(path.join(tmp,'layout/render.sh'),'sleep 2\necho should-not-complete\n');
  const timed=spawnSync(bash,['-s'],{input:[
    'CACHE_DIR='+quote(shellPath(path.join(tmp,'cache'))),
    'SCRIPT_DIR='+quote(shellPath(path.join(tmp,'bin'))),
    '. '+quote(shellPath(path.join(root,'bin/updates.sh'))),
    'LAYOUT_RENDER_TIMEOUT_SECONDS=1',
    'if run_layout '+quote(shellPath(path.join(tmp,'layout')))+'; then exit 1; fi'
  ].join('\n'),encoding:'utf8',timeout:10000});
  assert.equal(timed.status,0,timed.stderr);
  assert.ok(!timed.stdout.includes('should-not-complete'));
  console.log('PASS renderer timeout');
} finally { fs.rmSync(tmp,{recursive:true,force:true}); }