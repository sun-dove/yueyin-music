import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/lx_source/lx_bootstrap_v2.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime_v2.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/audio_quality.dart';

void main() {
  test('V2歌曲或档位取流失败不会误报整源初始化失败', () async {
    final sandbox = _Sandbox()
      ..error = 'resource not found'
      ..failAfterRequest = true;
    final runtime = LxSourceRuntimeV2(sandbox: sandbox, vendors: '');
    final source = LxSourceConfig(
      name: '测试源',
      version: '1',
      origin: Uri.parse('https://example.com/a.js'),
      script: 'fixture',
      sha256: 'hash',
      sources: const {
        'tx': ['128k'],
      },
    );
    await expectLater(
      runtime.resolve(
        source,
        const CustomSourceRequest(
          requestId: 'r',
          platform: PlatformType.qq,
          song: Song(
            id: 'mid',
            platform: PlatformType.qq,
            name: '歌',
            artists: [],
          ),
          quality: AudioLevel.low,
          purpose: CustomSourcePurpose.play,
        ),
      ),
      throwsA(
        isA<LxSourceException>().having((e) => e.code, '失败范围', 'resolve'),
      ),
    );
  });
  test('V2未定义的桌面接口显示名称，并关闭沙箱', () async {
    final sandbox = _Sandbox()..error = 'Buffer is not defined';
    final runtime = LxSourceRuntimeV2(sandbox: sandbox, vendors: '');
    await expectLater(
      runtime.inspect('fixture'),
      throwsA(
        isA<LxSourceException>().having(
          (e) => e.message,
          '接口名',
          contains('Buffer'),
        ),
      ),
    );
    expect(sandbox.closed, isTrue);
  });
  test('v2沙箱传入真实脚本信息与QQ数字ID、媒体MID', () async {
    final sandbox = _Sandbox();
    final runtime = LxSourceRuntimeV2(
      sandbox: sandbox,
      vendors: '',
      qqInfo: (_) async => {
        'songmid': 'mid',
        'songId': 7,
        'strMediaMid': 'media',
      },
    );
    final source = LxSourceConfig(
      name: '真实名称',
      version: '2',
      origin: Uri.parse('https://example.com/a.js'),
      script: '// @name 真实名称\n// @version 2',
      sha256: 'hash',
      sources: const {
        'tx': ['128k'],
      },
    );
    await runtime.resolve(
      source,
      const CustomSourceRequest(
        requestId: 'r',
        platform: PlatformType.qq,
        song: Song(
          id: 'mid',
          platform: PlatformType.qq,
          name: '歌',
          artists: [],
        ),
        quality: AudioLevel.low,
        purpose: CustomSourcePurpose.play,
      ),
    );
    expect(sandbox.codes.any((c) => c.contains('真实名称')), isTrue);
    final request = sandbox.request!;
    final info = (request['info'] as Map)['musicInfo'] as Map;
    expect(info['songId'], 7);
    expect(info['strMediaMid'], 'media');
    expect(info['songmid'], 'mid');
    expect(sandbox.closed, isTrue);
  });
  test('洛雪v2加密、字节缓冲和压缩黄金向量，超限明确失败', () async {
    final vendors =
        '${File('assets/lx-runtime/forge-1.3.1.min.js').readAsStringSync()}\n${File('assets/lx-runtime/pako-2.1.0.min.js').readAsStringSync()}';
    final bootstrap =
        '${lxV2Prelude(vendors, List.generate(65536, (i) => i % 256))}\n$lxV2Bootstrap';
    final process = await Process.start('node', [
      '-e',
      r'''
const vm=require('node:vm'), crypto=require('node:crypto');
let raw='';process.stdin.on('data',v=>raw+=v);process.stdin.on('end',async()=>{
try{
 const context=vm.createContext({});vm.runInContext(JSON.parse(raw),context,{timeout:4000});
 const run=code=>vm.runInContext(code,context,{timeout:2000});
 let passed=0;const check=(ok,label)=>{if(!ok)throw Error(label);passed++;};
 check(run("lx.utils.crypto.md5('abc')")==='900150983cd24fb0d6963f7d28e17f72','MD5');
 check(run("lx.utils.buffer.bufToString(lx.utils.buffer.from('悦音😀'))")==='悦音😀','UTF8');
 check(run("lx.utils.buffer.from('abc').toString('hex')")==='616263','Buffer.toString');
 check(run("lx.utils.buffer.bufToString('\\xff','hex')")==='ff','binary bufToString');
 check(run("(()=>{const a=new Uint8Array([1,2,3]);const b=lx.utils.buffer.from(a.buffer,1,1);a[1]=9;return b[0];})()")===9,'ArrayBuffer shared view');
 const expected=crypto.createCipheriv('aes-128-cbc',Buffer.alloc(16),Buffer.alloc(16));
 const encrypted=Buffer.concat([expected.update('hello'),expected.final()]).toString('hex');
 check(run("lx.utils.buffer.bufToString(lx.utils.crypto.aesEncrypt(lx.utils.buffer.from('hello'),'aes-128-cbc',new Uint8Array(16),new Uint8Array(16)),'hex')")===encrypted,'AES');
 for(const bits of [128,192,256])for(const mode of ['cbc','ecb','ctr','cfb','ofb']) {
   const algorithm=`aes-${bits}-${mode}`,c=crypto.createCipheriv(algorithm,Buffer.alloc(bits/8),mode==='ecb'?null:Buffer.alloc(16));
   const expected=Buffer.concat([c.update('中文和多块abcdefghijklmnop'),c.final()]).toString('hex');
   check(run(`lx.utils.crypto.aesEncrypt(lx.utils.buffer.from('中文和多块abcdefghijklmnop'),'${algorithm}',new Uint8Array(${bits/8}),new Uint8Array(16)).toString('hex')`)===expected,algorithm);
 }
 const keys=crypto.generateKeyPairSync('rsa',{modulusLength:1024,publicKeyEncoding:{type:'spki',format:'pem'},privateKeyEncoding:{type:'pkcs8',format:'pem'}});
 const input=Buffer.alloc(128);input[127]=42;
 const rsa=crypto.publicEncrypt({key:keys.publicKey,padding:crypto.constants.RSA_NO_PADDING},input).toString('hex');
 check(run(`lx.utils.buffer.bufToString(lx.utils.crypto.rsaEncrypt(lx.utils.buffer.from([42]),${JSON.stringify(keys.publicKey)}),'hex')`)===rsa,'RSA');
 check(run('lx.utils.crypto.randomBytes(16).length')===16,'random');
 check(await run("lx.utils.zlib.deflate(lx.utils.buffer.from('音乐')).then(b=>lx.utils.zlib.inflate(b)).then(b=>lx.utils.buffer.bufToString(b))")==='音乐','zlib');
 check(run("(()=>{try{lx.utils.buffer.from(new Uint8Array(524289));return false;}catch(e){return true;}})()"),'buffer bound');
 check(await run("lx.utils.zlib.inflate(pako.deflate(new Uint8Array(600000))).then(()=>false,()=>true)"),'inflate bound');
 check(run("[typeof require,typeof process,typeof fetch,typeof document].join(',')")==='undefined,undefined,undefined,undefined','isolation');
 console.log(JSON.stringify({passed}));
}catch(e){console.error(e.message);process.exitCode=1;}
});
''',
    ]);
    process.stdin.write(jsonEncode(bootstrap));
    await process.stdin.close();
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    final errorFuture = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    final output = await outputFuture;
    final error = await errorFuture;
    expect(code, 0, reason: error);
    expect(jsonDecode(output), {'passed': 27});
  });
}

class _Sandbox implements LxSandbox {
  bool failAfterRequest = false;
  String? error;
  final codes = <String>[];
  Map<String, dynamic>? request;
  bool closed = false;
  @override
  Future<void> create(String id) async {}
  @override
  Future<void> close(String id) async {
    closed = true;
  }

  @override
  Future<String> evaluate(String id, String code) async {
    codes.add(code);
    if (code.startsWith('__lxHost.resolve(')) {
      request = jsonDecode(code.substring(17, code.indexOf(');')));
    }
    if (code == '__lxHost.drain()') {
      return jsonEncode({
        if (error != null && (!failAfterRequest || request != null))
          'error': error,
        'ready': true,
        'sources': {
          'tx': {
            'type': 'music',
            'actions': ['musicUrl'],
            'qualitys': ['128k'],
          },
        },
        'done': request != null,
        'result': 'https://example.com/song.mp3',
        'queue': [],
      });
    }
    return '';
  }
}
