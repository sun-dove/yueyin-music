// 独立沙箱内的最小洛雪接口。文件/账号/原生网络均不暴露。
const lxBootstrap = r'''
(() => {
  let handler = null, ready = false, sources = {}, done = false, result = null, error = null;
  let serial = 0, total = 0;
  const queue = [], callbacks = new Map(), timers = new Map();
  const fail = e => { error = String(e && e.message || e).slice(0, 160); };
  globalThis.setTimeout = (fn, delay = 0, ...args) => {
    if (timers.size >= 64) throw Error('timer limit');
    const id = ++serial;
    timers.set(id, {fn: () => fn(...args), due: Date.now() + Math.max(0, Number(delay) || 0)});
    return id;
  };
  globalThis.clearTimeout = id => timers.delete(id);
  globalThis.setInterval = (fn, delay = 0, ...args) => {
    if (timers.size >= 64) throw Error('timer limit');
    const id = ++serial;
    const interval = Math.max(10, Number(delay) || 0);
    timers.set(id, {fn: () => fn(...args), due: Date.now() + interval, interval});
    return id;
  };
  globalThis.clearInterval = globalThis.clearTimeout;
  const maxBytes = 512 * 1024;
  const bounded = value => {
    if(value.length > maxBytes) throw Error('buffer size limit');
    return value;
  };
  const byteArray = value => {
    if(value instanceof ArrayBuffer) value = new Uint8Array(value);
    if(value instanceof DataView) value = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    return Array.from(bounded(value || []), byte => Number(byte) & 255);
  };
  const utf8Bytes = value => {
    const text = bounded(unescape(encodeURIComponent(bounded(String(value)))));
    return Array.from(text, char => char.charCodeAt(0));
  };
  const binaryString = value => {
    const bytes = byteArray(value); let result = '';
    for(let i=0;i<bytes.length;i+=8192) result += String.fromCharCode(...bytes.slice(i,i+8192));
    return result;
  };
  if(typeof globalThis.btoa !== 'function') globalThis.btoa = value => {
    const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    const input=bounded(String(value)); let output='';
    for(let i=0;i<input.length;i+=3){
      const a=input.charCodeAt(i)&255,b=i+1<input.length?input.charCodeAt(i+1)&255:NaN,c=i+2<input.length?input.charCodeAt(i+2)&255:NaN;
      const n=(a<<16)|((b||0)<<8)|(c||0);
      output+=chars[(n>>18)&63]+chars[(n>>12)&63]+(Number.isNaN(b)?'=':chars[(n>>6)&63])+(Number.isNaN(c)?'=':chars[n&63]);
    } return output;
  };
  if(typeof globalThis.atob !== 'function') globalThis.atob = value => {
    const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    const input=bounded(String(value)).replace(/\s/g,''); let output='';
    for(let i=0;i<input.length;i+=4){
      const a=chars.indexOf(input[i]),b=chars.indexOf(input[i+1]),c=chars.indexOf(input[i+2]),d=chars.indexOf(input[i+3]);
      const n=(a<<18)|(b<<12)|((c&63)<<6)|(d&63);
      output+=String.fromCharCode((n>>16)&255); if(c!==64&&c!==-1) output+=String.fromCharCode((n>>8)&255); if(d!==64&&d!==-1) output+=String.fromCharCode(n&255);
    } return output;
  };
  if(typeof globalThis.TextEncoder !== 'function') globalThis.TextEncoder = class { encode(value){ return Uint8Array.from(utf8Bytes(value)); } };
  if(typeof globalThis.TextDecoder !== 'function') globalThis.TextDecoder = class { decode(value){ return decodeURIComponent(escape(binaryString(value))); } };
  const noop = () => {};
  globalThis.console = Object.freeze({log:noop, info:noop, warn:noop, error:noop, debug:noop, group:noop, groupEnd:noop, time:noop, timeEnd:noop});
  const unavailable = name => () => {throw Error('unsupported: ' + name);};
  globalThis.lx = Object.freeze({
    EVENT_NAMES: Object.freeze({request:'request', inited:'inited', updateAlert:'updateAlert'}),
    env:'mobile', version:'2.0.0',
    currentScriptInfo: {name:'custom', version:'', description:'', author:'', homepage:''},
    on: (event, callback) => {
      if(event !== 'request' || typeof callback !== 'function') return Promise.reject(Error('unsupported event'));
      handler = callback; return Promise.resolve();
    },
    send: (event, value) => {
      if(event === 'updateAlert') return Promise.resolve();
      if(event !== 'inited') return Promise.reject(Error('unsupported event'));
      if(!value || value.status !== true || !value.sources || !handler) { fail('initialization failed'); return Promise.resolve(); }
      sources = value.sources; ready = true; return Promise.resolve();
    },
    request: (url, options, callback) => {
      if(typeof options === 'function') {callback=options; options={};}
      if(++total > 16 || callbacks.size >= 4) throw Error('request limit');
      const id = ++serial;
      callbacks.set(id, callback);
      queue.push({id, url:String(url), options:options || {}});
      return () => {callbacks.delete(id); queue.push({id, cancel:true});};
    },
    utils: Object.freeze({
      crypto: new Proxy({}, {get: (_, name) => unavailable('utils.crypto.'+String(name))}),
      buffer: Object.freeze({
        from(value, format='utf8') {
          if(Array.isArray(value) || ArrayBuffer.isView(value) || value instanceof ArrayBuffer) return byteArray(value);
          value = bounded(String(value));
          if(format === 'base64') return Array.from(atob(String(value)), char => char.charCodeAt(0));
          if(format === 'hex') { const text=value; const result=[]; for(let i=0;i+1<text.length;i+=2) { const pair=text.slice(i,i+2); if(!/^[a-f0-9]{2}$/i.test(pair)) break; result.push(parseInt(pair,16)); } return result; }
          if(format === 'binary' || format === 'latin1') return Array.from(String(value), char => char.charCodeAt(0)&255);
          return utf8Bytes(value);
        },
        bufToString(value, format='utf8') {
          const binary=binaryString(value);
          if(format === 'base64') return btoa(binary);
          if(format === 'hex') return Array.from(value || [], byte => (byte&255).toString(16).padStart(2,'0')).join('');
          if(format === 'binary' || format === 'latin1') return binary;
          return decodeURIComponent(escape(binary));
        }
      }),
      zlib: new Proxy({}, {get: (_, name) => unavailable('utils.zlib.'+String(name))})
    })
  });
  Object.defineProperty(globalThis, '__lxHost', {value:Object.freeze({
    loadError(value) { fail(value); },
    drain() {
      for(const [id,timer] of Array.from(timers)) if(timer.due <= Date.now()) {
        if(timer.interval) timer.due = Date.now() + timer.interval; else timers.delete(id);
        try {timer.fn();} catch(e) {fail(e);}
      }
      return JSON.stringify({ready,sources,done,result,error,queue:queue.splice(0)});
    },
    response(id, response) {
      const callback=callbacks.get(id); callbacks.delete(id);
      if(callback) try {callback(response.error ? Error(response.error) : null, response.error ? null : response, response.body);} catch(e) {fail(e);}
    },
    resolve(request) {
      done=false; result=null;
      Promise.resolve().then(() => handler(request)).then(value => {result=value; done=true;}, fail);
    }
  }), writable:false, configurable:false});
})();
''';
