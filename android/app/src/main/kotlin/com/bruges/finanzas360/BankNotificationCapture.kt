package com.bruges.finanzas360

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import android.util.Base64
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.util.Locale

data class BankNotificationRecord(
    val id: String,
    val source: String,
    val packageName: String,
    val kind: String?,
    val amountMinor: Long?,
    val currency: String?,
    val observedAt: Long,
    val counterparty: String?,
    val reference: String?,
    val method: String?,
    val reportedStatus: String?,
    val reviewReason: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "source" to source,
        "packageName" to packageName,
        "kind" to kind,
        "amountMinor" to amountMinor,
        "currency" to currency,
        "observedAt" to observedAt,
        "counterparty" to counterparty,
        "reference" to reference,
        "method" to method,
        "reportedStatus" to reportedStatus,
        "reviewReason" to reviewReason,
    )

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("source", source)
        put("packageName", packageName)
        put("kind", kind ?: JSONObject.NULL)
        put("amountMinor", amountMinor ?: JSONObject.NULL)
        put("currency", currency ?: JSONObject.NULL)
        put("observedAt", observedAt)
        put("counterparty", counterparty ?: JSONObject.NULL)
        put("reference", reference ?: JSONObject.NULL)
        put("method", method ?: JSONObject.NULL)
        put("reportedStatus", reportedStatus ?: JSONObject.NULL)
        put("reviewReason", reviewReason ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(json: JSONObject) = BankNotificationRecord(
            id = json.getString("id"),
            source = json.getString("source"),
            packageName = json.getString("packageName"),
            kind = json.optString("kind").takeIf { it.isNotBlank() },
            amountMinor = if (json.isNull("amountMinor")) null else json.optLong("amountMinor"),
            currency = json.optString("currency").takeIf { it.isNotBlank() },
            observedAt = json.getLong("observedAt"),
            counterparty = json.optString("counterparty").takeIf { it.isNotBlank() },
            reference = json.optString("reference").takeIf { it.isNotBlank() },
            method = json.optString("method").takeIf { it.isNotBlank() },
            reportedStatus = json.optString("reportedStatus").takeIf { it.isNotBlank() },
            reviewReason = json.optString("reviewReason").takeIf { it.isNotBlank() },
        )
    }
}

object BankNotificationCapture {
    private const val preferenceFile = "bank_notification_capture"
    private const val enabledKey = "enabled_packages"
    private const val queueKey = "pending_records"
    private const val encryptionKeyAlias = "bruges-bank-queue-v1"

    val packageNames = linkedMapOf(
        "com.nequi.MobileApp" to "Nequi",
        "co.com.bancolombia.personas.superapp" to "Mi Bancolombia",
        "com.davivienda.daviplataapp" to "DaviPlata",
        "com.avalsolucionesdigitalessa.dale_app_embedded" to "dale!",
        "com.movilred.subscriber" to "MOVii",
    )

    fun enabledPackages(context: Context): Set<String> =
        context.getSharedPreferences(preferenceFile, Context.MODE_PRIVATE)
            .getStringSet(enabledKey, emptySet())
            .orEmpty()
            .intersect(packageNames.keys)

    fun setEnabledPackages(context: Context, requested: Collection<String>) {
        val allowed = requested.toSet().intersect(packageNames.keys)
        context.getSharedPreferences(preferenceFile, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(enabledKey, allowed)
            .commit()
    }

    @Synchronized
    fun enqueue(context: Context, record: BankNotificationRecord) {
        val preferences = context.getSharedPreferences(preferenceFile, Context.MODE_PRIVATE)
        val current = readQueue(decryptQueue(preferences.getString(queueKey, null)))
        val previous = (0 until current.length()).map { current.getJSONObject(it) }
        if (previous.any { it.optString("id") == record.id }) return
        current.put(record.toJson())
        preferences.edit().putString(queueKey, encryptQueue(current.toString())).commit()
    }

    @Synchronized
    fun pending(context: Context): List<Map<String, Any?>> {
        val preferences = context.getSharedPreferences(preferenceFile, Context.MODE_PRIVATE)
        val queue = readQueue(decryptQueue(preferences.getString(queueKey, null)))
        return (0 until queue.length()).map { BankNotificationRecord.fromJson(queue.getJSONObject(it)).toMap() }
    }

    @Synchronized
    fun acknowledge(context: Context, ids: Set<String>) {
        if (ids.isEmpty()) return
        val preferences = context.getSharedPreferences(preferenceFile, Context.MODE_PRIVATE)
        val queue = readQueue(decryptQueue(preferences.getString(queueKey, null)))
        val kept = JSONArray()
        for (index in 0 until queue.length()) {
            val row = queue.getJSONObject(index)
            if (row.optString("id") !in ids) kept.put(row)
        }
        preferences.edit().putString(queueKey, encryptQueue(kept.toString())).commit()
    }

    fun parse(
        packageName: String,
        notificationKey: String,
        title: String,
        text: String,
        observedAt: Long,
    ): BankNotificationRecord? {
        val source = packageNames[packageName] ?: return null
        if (notificationKey.isBlank()) return null
        val fullText = "$title $text"
        val normalized = fullText.lowercase(Locale.ROOT)
        val hasCue = Regex("\\b(recibiste|recibieron|recibida|recibido|abono|consignaci[oó]n|transferencia|transfirieron|pagaste|pag[oó]|compra|compraste|transferiste|enviaste|retiro|retiraste|d[eé]bito|debito|pago)\\b").containsMatchIn(normalized)
        if (!hasCue) return null

        val isIncome = Regex("\\b(recibiste|recibieron|recibida|recibido|abono|consignaci[oó]n\\s+recibida|transferencia\\s+recibida|te\\s+lleg[oó]|te\\s+enviaron|te\\s+transfirieron)\\b").containsMatchIn(normalized)
        val isExpense = Regex("\\b(pagaste|pag[oó]|compra|compraste|transferiste|enviaste|transferencia\\s+enviada|retiro|retiraste|d[eé]bito|debito|pago\\s+aprobado|pago\\s+realizado)\\b").containsMatchIn(normalized)
        val kind = when {
            isIncome == isExpense -> null
            isIncome -> "income"
            else -> "expense"
        }

        val amountMatches = Regex("(?:COP|COL\\$|\\$)\\s*([0-9][0-9., ]*)", RegexOption.IGNORE_CASE)
            .findAll(fullText).toList()
        val amountMinor = if (amountMatches.size == 1) {
            amountMatches.single().groupValues[1].replace(Regex("[., ]"), "").toLongOrNull()?.takeIf { it > 0 }
        } else null

        val reference = Regex("\\b(?:referencia|ref\\.?|comprobante)\\s*[:#-]?\\s*([A-Z0-9-]{4,40})", RegexOption.IGNORE_CASE)
            .find(fullText)?.groupValues?.get(1)
        val partyMarker = if (kind == "income") "de" else "(?:a|para)"
        val counterparty = if (kind == null) null else Regex(
            "\\b$partyMarker\\s+([A-Za-zÁÉÍÓÚÜÑáéíóúüñ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ .'-]{1,38}?)(?=[.,;\\n]|$)",
            RegexOption.IGNORE_CASE,
        ).find(fullText)?.groupValues?.get(1)?.trim()
        val method = Regex("\\b(Bre-B|PSE|QR|tarjeta|llave)\\b", RegexOption.IGNORE_CASE)
            .find(normalized)?.groupValues?.get(1)
        val statusText = Regex("\\b(completada|completado|exitosa|exitoso|realizada|realizado|pendiente|procesando|rechazada|rechazado|fallida|fallido)\\b")
            .find(normalized)?.groupValues?.get(1)
        val reportedStatus = when {
            statusText == null -> null
            Regex("pendiente|procesando").containsMatchIn(statusText) -> "pending_reported"
            Regex("rechazad|fallid").containsMatchIn(statusText) -> "failed_reported"
            else -> "completed_reported"
        }
        val referenceOrKey = reference ?: notificationKey
        val id = sha256("$packageName|$referenceOrKey|${kind ?: "unknown"}|${amountMinor ?: "unknown"}")

        return BankNotificationRecord(
            id = "bank:$id",
            source = source,
            packageName = packageName,
            kind = kind,
            amountMinor = amountMinor,
            currency = if (amountMinor == null) null else "COP",
            observedAt = observedAt,
            counterparty = counterparty,
            reference = reference,
            method = method,
            reportedStatus = reportedStatus,
            reviewReason = when {
                kind == null -> "Tipo de movimiento ambiguo"
                amountMinor == null -> "Importe no identificado"
                else -> null
            },
        )
    }

    private fun readQueue(raw: String?): JSONArray = try {
        JSONArray(raw ?: "[]")
    } catch (error: Exception) {
        throw IllegalStateException("Stored notification queue is invalid", error)
    }

    private fun encryptQueue(plainText: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val payload = cipher.iv + encrypted
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decryptQueue(encoded: String?): String? {
        if (encoded.isNullOrBlank()) return "[]"
        if (encoded.startsWith("[")) return encoded
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        val ivLength = 12
        require(payload.size > ivLength) { "Invalid encrypted notification queue" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateKey(),
            GCMParameterSpec(128, payload.copyOfRange(0, ivLength)),
        )
        return String(cipher.doFinal(payload.copyOfRange(ivLength, payload.size)), Charsets.UTF_8)
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(encryptionKeyAlias, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                encryptionKeyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }
}
