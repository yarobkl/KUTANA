const assert = require('node:assert/strict');
const handler = require('./api/share');
const uuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
async function request(kind, id) {
  const result = { headers: {} };
  const res = { setHeader: (k,v) => result.headers[k] = v, status: n => ({ send: body => { result.status = n; result.body = body; } }) };
  await handler({ query:{kind,id}, headers:{host:'example.invalid'} },res);
  return result;
}
(async () => {
  const original = global.fetch;
  global.fetch = async (url) => { assert.match(url, /listings/); return {ok:true,json:async()=>[{title:'<script>bad</script>',description:'Texte & détail',city:'Paris',price_xaf:100,status:'sold'}]}; };
  let response = await request('listing',uuid);
  assert.equal(response.status,200);
  assert.match(response.body,/&lt;script&gt;bad&lt;\/script&gt;/);
  assert.doesNotMatch(response.body,/<script>bad/);
  assert.match(response.body,/Vendu/);
  assert.match(response.body,/Texte &amp; détail/);
  assert.equal((await request('listing','../autre')).status,404);
  global.fetch = async () => ({ok:true,json:async()=>[]});
  assert.equal((await request('job',uuid)).status,404);
  global.fetch = async () => {throw Error('offline')};
  assert.equal((await request('job',uuid)).status,503);
  global.fetch = original;
  console.log('Public share handler tests: OK');
})().catch(e => { console.error(e); process.exitCode = 1; });
