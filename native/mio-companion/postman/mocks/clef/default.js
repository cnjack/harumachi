// Consumer dependency mock, generated from clef.openapi.yaml then extended with
// explicit error cases. This is a test double, not clef-omni inference.
const http = require('http');
http.createServer((req, res) => {
  const reply = (status, body) => {
    res.writeHead(status, {'Content-Type': 'application/json'});
    res.end(JSON.stringify(body));
  };
  if (req.method !== 'POST' || req.url !== '/v1/systemone') return reply(501, {error: 'Endpoint not modeled'});
  const body = req.body;
  if (!body || body.model !== 'clef-omni' || !body.state || !body.questions ||
      !['mood','reaction'].every(k => body.questions[k]?.type === 'choice' && body.questions[k]?.criteria && body.questions[k]?.instructions)) {
    return reply(400, {error: 'Request does not match the consumer contract'});
  }
  const text = body.state.summary;
  if (text === '__redirect__') { res.writeHead(302, {'Location':'http://192.168.10.202:8098/v1/systemone'}); return res.end(); }
  if (text === '__status500__') return reply(500, {error: 'Simulated upstream inference error'});
  if (text === '__html__') { res.writeHead(502, {'Content-Type':'text/html'}); return res.end('<h1>Bad gateway</h1>'); }
  if (text === '__invalid__') return reply(200, {answers: {}});
  const confidence = text === '__lowconfidence__' ? 0.3 : 0.97;
  const result = {model: text === '__wrongmodel__' ? 'wrong-model' : 'clef-omni', answers: {
    mood: {type:'choice', choice:'happy', confidence},
    reaction: {type:'choice', choice: text === '__unknown__' ? 'run_shell' : 'notice', confidence}
  }};
  if (text === '__timeout__') return setTimeout(() => reply(200, result), 1500);
  reply(200, result);
}).listen(process.env.PORT || 4911);
