package com.tverdohleb.tacca

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * L'activity dell'app, più una cosa sola: riceve i testi che le altre app
 * condividono con Tacca (`ACTION_SEND` con `text/plain`, dichiarato nel
 * manifest) e li tiene da parte finché il Dart non li chiede.
 *
 * È un *pull* e non un push perché il testo può arrivare ad app spenta
 * (`onCreate` con l'intent, prima che il motore Dart esista) oppure ad app
 * viva (`onNewIntent`, grazie a `launchMode="singleTask"`): in entrambi i
 * casi l'activity torna in primo piano, e il Dart svuota la coda a ogni
 * rientro. Nessun database e nessuna logica qui: il contenuto lo interpreta
 * `AiPasteImportCubit`.
 */
class MainActivity : FlutterActivity() {
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        result.success(pendingSharedText)
                        pendingSharedText = null
                    }
                    else -> result.notImplemented()
                }
            }
        // Avvio a freddo da "Condividi": l'intent è quello di lancio.
        takeSharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeSharedText(intent)
    }

    private fun takeSharedText(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        if (intent.type?.startsWith("text/") != true) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (text.isNullOrBlank()) return
        pendingSharedText = text
        // Consumato: una rotazione o un ripristino dell'activity rileggono
        // l'intent, e lo stesso testo non deve arrivare due volte.
        intent.action = null
        intent.removeExtra(Intent.EXTRA_TEXT)
    }

    private companion object {
        /** Lo stesso nome di `PlatformSharedTextReceiver.channelName` in Dart. */
        const val CHANNEL = "tacca/shared_text"
    }
}
