import 'dart:convert';

import 'lx_bootstrap.dart';

/// 只在新增运行时使用；旧 bootstrap 的公开内容保持不变。
final lxV2Bootstrap = lxBootstrap
    .replaceFirst(
      "crypto: new Proxy({}, {get: (_, name) => unavailable('utils.crypto.'+String(name))})",
      'crypto: __lxV2.crypto',
    )
    .replaceFirst(
      "zlib: new Proxy({}, {get: (_, name) => unavailable('utils.zlib.'+String(name))})",
      'zlib: __lxV2.zlib',
    )
    .replaceFirst(
      RegExp(r'buffer: Object\.freeze\(\{[\s\S]*?\n      \}\),'),
      'buffer: __lxV2.buffer,',
    )
    .replaceFirst(
      "currentScriptInfo: {name:'custom', version:'', description:'', author:'', homepage:''}",
      "currentScriptInfo: globalThis.__lxScriptInfo || {name:'custom',version:'',description:'',author:'',homepage:''}",
    );

String lxV2Prelude(String vendors, List<int> randomSeed) =>
    '''
globalThis.self=globalThis;
globalThis.crypto=(()=>{
  const pool=Uint8Array.from(${jsonEncode(randomSeed)});let offset=0;
  return Object.freeze({getRandomValues(value){
    const bytes=new Uint8Array(value.buffer,value.byteOffset,value.byteLength);
    if(offset+bytes.length>pool.length)throw Error('random byte budget exceeded');
    bytes.set(pool.subarray(offset,offset+bytes.length));offset+=bytes.length;return value;
  }});
})();
(function(){const window=globalThis,self=globalThis;
$vendors
}).call(globalThis);
$lxV2Utilities
''';

const lxV2Utilities = r'''
const __lxV2=(()=>{
  const limit=524288;
  const bound=n=>{if(!Number.isInteger(n)||n<0||n>limit)throw Error('buffer size limit');return n;};
  const raw=bytes=>{let out='';for(let i=0;i<bytes.length;i+=8192)out+=String.fromCharCode(...bytes.subarray(i,i+8192));return out;};
  class Bytes extends Uint8Array {
    toString(format='utf8',start=0,end=this.length){
      const b=raw(this.subarray(start,end));
      switch(String(format).toLowerCase()){
        case 'hex':return forge.util.bytesToHex(b);
        case 'base64':return forge.util.encode64(b);
        case 'binary':case 'latin1':return b;
        case 'utf8':case 'utf-8':return forge.util.decodeUtf8(b);
        default:throw Error('unsupported encoding');
      }
    }
    toJSON(){return {type:'Buffer',data:Array.from(this)};}
    equals(other){return this.length===other.length&&this.every((v,i)=>v===other[i]);}
  }
  const from=(value,format='utf8',length)=>{
    if(typeof value==='string'){
      if(value.length>limit*2)throw Error('buffer size limit');
      let text;
      switch(String(format).toLowerCase()){
        case 'hex':{
          const match=value.match(/^(?:[0-9a-fA-F]{2})*/);text=forge.util.hexToBytes(match[0]);break;
        }
        case 'base64':text=forge.util.decode64(value);break;
        case 'binary':case 'latin1':text=value;break;
        case 'utf8':case 'utf-8':text=forge.util.encodeUtf8(value);break;
        default:throw Error('unsupported encoding');
      }
      const result=new Bytes(bound(text.length));for(let i=0;i<text.length;i++)result[i]=text.charCodeAt(i)&255;return result;
    }
    if(value instanceof ArrayBuffer){
      const offset=typeof format==='number'?format:0;
      return new Bytes(value,offset,bound(length===undefined?value.byteLength-offset:length));
    } else if(value instanceof DataView)value=new Uint8Array(value.buffer,value.byteOffset,value.byteLength);
    if(value&&value.type==='Buffer'&&Array.isArray(value.data))value=value.data;
    if(!Array.isArray(value)&&!ArrayBuffer.isView(value))throw TypeError('buffer input required');
    const result=new Bytes(bound(value.length));result.set(value);return result;
  };
  const binary=value=>raw(typeof value==='string'?from(value):from(value));
  const crypto=Object.freeze({
    md5(value){const md=forge.md.md5.create();md.update(binary(value));return md.digest().toHex();},
    randomBytes(size){const result=new Bytes(bound(size));globalThis.crypto.getRandomValues(result);return result;},
    aesEncrypt(value,mode,key,iv){
      const match=/^aes-(128|192|256)-(cbc|ecb|ctr|cfb|ofb)$/i.exec(mode);
      if(!match)throw Error('unsupported: utils.crypto.aesEncrypt.mode');
      const k=from(key),data=from(value),isEcb=match[2].toLowerCase()==='ecb';
      if(k.length!==Number(match[1])/8)throw Error('invalid AES key length');
      const vector=isEcb?null:from(iv);
      if(vector&&vector.length!==16)throw Error('invalid AES IV length');
      const cipher=forge.cipher.createCipher('AES-'+match[2].toUpperCase(),raw(k));
      cipher.start({iv:vector?raw(vector):null});cipher.update(forge.util.createBuffer(raw(data)));
      if(!cipher.finish())throw Error('AES encryption failed');return from(cipher.output.getBytes(),'binary');
    },
    rsaEncrypt(value,key){
      const bytes=from(value);if(bytes.length>128)throw Error('RSA input exceeds 128 bytes');
      const input='\x00'.repeat(128-bytes.length)+raw(bytes);
      return from(forge.pki.publicKeyFromPem(key).encrypt(input,'RAW'),'binary');
    }
  });
  const compress=(value,inflate)=>Promise.resolve().then(()=>{
    const input=from(value),chunks=[];let total=0;
    const stream=inflate?new pako.Inflate({chunkSize:16384}):new pako.Deflate({chunkSize:16384});
    stream.onData=chunk=>{total+=chunk.length;bound(total);chunks.push(chunk);};
    stream.push(input,true);if(stream.err)throw Error(inflate?'inflate failed':'deflate failed');
    const result=new Bytes(total);let offset=0;for(const chunk of chunks){result.set(chunk,offset);offset+=chunk.length;}return result;
  });
  const named=(value,name)=>new Proxy(Object.freeze(value),{get:(target,key)=>key in target ? target[key] :
    ()=>{throw Error('unsupported: utils.'+name+'.'+String(key));}});
  return Object.freeze({crypto:named(crypto,'crypto'),buffer:named({from,bufToString:(value,format='utf8')=>from(value,'binary').toString(format)},'buffer'),
    zlib:named({inflate:value=>compress(value,true),deflate:value=>compress(value,false)},'zlib')});
})();
''';
