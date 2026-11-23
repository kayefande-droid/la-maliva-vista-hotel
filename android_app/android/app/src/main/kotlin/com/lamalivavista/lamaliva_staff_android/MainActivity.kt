package com.lamalivavista.lamaliva_staff_android

import android.content.Context
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lamaliva/print")
            .setMethodCallHandler { call, result ->
                if (call.method != "printPdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name") ?: "invoice"
                if (bytes == null) {
                    result.error("no_bytes", "There is no invoice to print.", null)
                    return@setMethodCallHandler
                }
                try {
                    printPdf(bytes, name)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("print_failed", error.message, null)
                }
            }
    }

    /** Opens Android's print dialog with the generated invoice as the document. */
    private fun printPdf(bytes: ByteArray, jobName: String) {
        val safe = jobName.replace(Regex("[^A-Za-z0-9 _-]"), "").trim().ifEmpty { "invoice" }
        val file = File(cacheDir, "$safe.pdf")
        file.writeBytes(bytes)
        val manager = getSystemService(Context.PRINT_SERVICE) as PrintManager
        manager.print(
            "La Maliva Vista - $safe",
            object : PrintDocumentAdapter() {
                override fun onLayout(
                    oldAttributes: PrintAttributes?,
                    newAttributes: PrintAttributes?,
                    cancellationSignal: CancellationSignal?,
                    callback: LayoutResultCallback,
                    extras: Bundle?,
                ) {
                    if (cancellationSignal?.isCanceled == true) {
                        callback.onLayoutCancelled()
                        return
                    }
                    val info = PrintDocumentInfo.Builder("$safe.pdf")
                        .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                        .build()
                    callback.onLayoutFinished(info, true)
                }

                override fun onWrite(
                    pages: Array<out PageRange>?,
                    destination: ParcelFileDescriptor,
                    cancellationSignal: CancellationSignal?,
                    callback: WriteResultCallback,
                ) {
                    FileInputStream(file).use { input ->
                        val output = FileOutputStream(destination.fileDescriptor)
                        input.copyTo(output)
                        output.flush()
                    }
                    callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                }
            },
            PrintAttributes.Builder().build(),
        )
    }
}
