package com.bruges.finanzas360

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.Intent
import android.net.Uri
import android.app.Activity
import android.content.ComponentName
import android.provider.Settings
import java.io.IOException

class MainActivity : FlutterActivity() {
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportContents: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.bruges.finanzas360/data")
            .setMethodCallHandler { call, result ->
                if (call.method == "dataDirectory") {
                    result.success(applicationContext.filesDir.absolutePath)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.bruges.finanzas360/external")
            .setMethodCallHandler { call, result ->
                if (call.method == "openUrl") {
                    val rawUrl = call.arguments as? String
                    val uri = rawUrl?.let { Uri.parse(it) }
                    if (uri == null || uri.scheme != "https" || uri.host != "wa.me") {
                        result.error("INVALID_URL", "Only WhatsApp HTTPS links are allowed", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("OPEN_FAILED", error.message, null)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.bruges.finanzas360/export")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveExport") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingExportResult != null) {
                    result.error("EXPORT_BUSY", "Ya hay una exportación abierta.", null)
                    return@setMethodCallHandler
                }
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType")
                val contents = call.argument<String>("contents")
                val validName = fileName?.matches(
                    Regex("BRUGES-FINANZAS-360-[0-9]+\\.(csv|json)")
                ) == true
                if (!validName || mimeType !in setOf("text/csv", "application/json") || contents == null) {
                    result.error("INVALID_EXPORT", "Los datos de exportación no son válidos.", null)
                    return@setMethodCallHandler
                }
                pendingExportResult = result
                pendingExportContents = contents.toByteArray(Charsets.UTF_8)
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mimeType
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }
                try {
                    startActivityForResult(intent, EXPORT_REQUEST_CODE)
                } catch (error: Exception) {
                    pendingExportResult = null
                    pendingExportContents = null
                    result.error("EXPORT_FAILED", error.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.bruges.finanzas360/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getEnabledBankPackages" -> {
                        result.success(BankNotificationCapture.enabledPackages(this).toList())
                    }
                    "setEnabledBankPackages" -> {
                        val packages = call.argument<List<String>>("packages").orEmpty()
                        BankNotificationCapture.setEnabledPackages(this, packages)
                        result.success(BankNotificationCapture.enabledPackages(this).toList())
                    }
                    "pendingBankObservations" -> {
                        result.success(BankNotificationCapture.pending(this))
                    }
                    "ackBankObservations" -> {
                        val ids = call.argument<List<String>>("ids").orEmpty().toSet()
                        BankNotificationCapture.acknowledge(this, ids)
                        result.success(true)
                    }
                    "openListenerSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("SETTINGS_FAILED", error.message, null)
                        }
                    }
                    "hasListenerAccess" -> {
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            "enabled_notification_listeners",
                        ).orEmpty()
                        val component = ComponentName(this, BankNotificationListenerService::class.java)
                        result.success(
                            enabled.split(":").any {
                                ComponentName.unflattenFromString(it) == component
                            },
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.bruges.finanzas360/bank-notifications")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    BankNotificationEvents.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    BankNotificationEvents.sink = null
                }
            })
    }

    @Deprecated("Use the platform document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != EXPORT_REQUEST_CODE) return
        val result = pendingExportResult ?: return
        val contents = pendingExportContents
        pendingExportResult = null
        pendingExportContents = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null || contents == null) {
            result.success(null)
            return
        }
        try {
            val output = contentResolver.openOutputStream(uri)
                ?: throw IOException("No se pudo abrir el archivo seleccionado.")
            output.use { it.write(contents) }
            result.success(uri.toString())
        } catch (error: Exception) {
            result.error("EXPORT_WRITE_FAILED", error.message, null)
        }
    }

    companion object {
        private const val EXPORT_REQUEST_CODE = 7360
    }
}
