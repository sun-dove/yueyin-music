package com.mconnect.mconnect

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.javascriptengine.IsolateStartupParameters
import androidx.javascriptengine.JavaScriptIsolate
import androidx.javascriptengine.JavaScriptSandbox
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/** 仅视频入口注册。沙箱不持有账号、文件或联网桥。 */
class VideoLxPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executor { main.post(it) }
    private var sandboxFuture: ListenableFuture<JavaScriptSandbox>? = null
    private var sandbox: JavaScriptSandbox? = null
    private val pending = mutableSetOf<String>()
    private val isolates = mutableMapOf<String, JavaScriptIsolate>()
    private var detached = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "app.videomusic.player/lx_sandbox")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id == null || id.length > 160) {
            result.error("arguments", "Invalid session", null)
            return
        }
        when (call.method) {
            "create" -> create(id, result)
            "evaluate" -> {
                val isolate = isolates[id]
                val code = call.argument<String>("code")
                if (isolate == null || code == null || code.toByteArray(Charsets.UTF_8).size > 2 * 1024 * 1024) {
                    result.error("script", "Invalid evaluation", null)
                    return
                }
                try {
                    val future = isolate.evaluateJavaScriptAsync(code)
                    future.addListener({
                        try { result.success(future.get()) }
                        catch (_: Exception) { result.error("script", "Script evaluation failed", null) }
                    }, executor)
                } catch (_: Exception) { result.error("script", "Script evaluation failed", null) }
            }
            "close" -> {
                pending.remove(id)
                isolates.remove(id)?.close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun create(id: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 26 || !JavaScriptSandbox.isSupported()) {
            result.error("unsupported", "JavaScript sandbox is unavailable", null)
            return
        }
        if (isolates.containsKey(id) || pending.contains(id) || isolates.size + pending.size >= 3) {
            result.error("busy", "Sandbox session limit", null)
            return
        }
        pending.add(id)
        try {
            val future = sandboxFuture ?: JavaScriptSandbox.createConnectedInstanceAsync(context).also { sandboxFuture = it }
            future.addListener({
                try {
                    val engine = future.get()
                    sandbox = engine
                    if (detached) { engine.close(); result.error("cancelled", "Engine closed", null); return@addListener }
                    if (!pending.remove(id)) { result.error("cancelled", "Session cancelled", null); return@addListener }
                    if (!engine.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_ISOLATE_TERMINATION) ||
                        !engine.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_ISOLATE_MAX_HEAP_SIZE) ||
                        !engine.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_EVALUATE_WITHOUT_TRANSACTION_LIMIT)) {
                        result.error("unsupported", "Required isolation features are unavailable", null)
                        return@addListener
                    }
                    val settings = IsolateStartupParameters().apply {
                        setMaxHeapSizeBytes(32L * 1024 * 1024)
                        setMaxEvaluationReturnSizeBytes(256 * 1024)
                    }
                    isolates[id] = engine.createIsolate(settings)
                    result.success(null)
                } catch (_: Exception) {
                    pending.remove(id)
                    sandboxFuture = null
                    sandbox?.close()
                    sandbox = null
                    result.error("unsupported", "Unable to create isolated runtime", null)
                }
            }, executor)
        } catch (_: Exception) {
            pending.remove(id)
            sandboxFuture = null
            result.error("unsupported", "Unable to connect to isolated runtime", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        channel.setMethodCallHandler(null)
        pending.clear()
        isolates.values.forEach { it.close() }
        isolates.clear()
        sandbox?.close()
        sandbox = null
        sandboxFuture = null
    }
}
