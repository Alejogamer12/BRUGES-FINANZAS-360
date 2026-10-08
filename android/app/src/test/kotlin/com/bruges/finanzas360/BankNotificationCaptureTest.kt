package com.bruges.finanzas360

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BankNotificationCaptureTest {
    @Test
    fun parsesOnlySelectedEntityFamiliesIntoStructuredFields() {
        val record = BankNotificationCapture.parse(
            packageName = "com.nequi.MobileApp",
            notificationKey = "opaque-system-key",
            title = "Transferencia recibida",
            text = "Recibiste $ 25.000 de Ana Pérez. Ref: ABC12345",
            observedAt = 1_791_471_600_000,
        )

        assertNotNull(record)
        assertEquals("Nequi", record?.source)
        assertEquals("income", record?.kind)
        assertEquals(25_000L, record?.amountMinor)
        assertEquals("COP", record?.currency)
        assertEquals("Ana Pérez", record?.counterparty)
        assertEquals("ABC12345", record?.reference)
        assertEquals(null, record?.reviewReason)
    }

    @Test
    fun keepsAmbiguousOperationsAsReviewCandidates() {
        val record = BankNotificationCapture.parse(
            packageName = "com.davivienda.daviplataapp",
            notificationKey = "ambiguous-key",
            title = "Movimiento",
            text = "Pagaste $ 10.000 y recibiste $ 20.000",
            observedAt = 1_791_471_600_000,
        )

        assertNotNull(record)
        assertEquals(null, record?.kind)
        assertEquals(null, record?.amountMinor)
        assertEquals("Tipo de movimiento ambiguo", record?.reviewReason)
    }

    @Test
    fun rejectsUnselectedPackagesAndNonTransactionAlerts() {
        assertNull(
            BankNotificationCapture.parse(
                packageName = "com.example.messaging",
                notificationKey = "private-message",
                title = "Transferencia recibida",
                text = "Recibiste $ 25.000",
                observedAt = 1_791_471_600_000,
            ),
        )
        assertNull(
            BankNotificationCapture.parse(
                packageName = "com.nequi.MobileApp",
                notificationKey = "promotion",
                title = "Oferta especial",
                text = "Recarga hoy y gana premios",
                observedAt = 1_791_471_600_000,
            ),
        )
    }

    @Test
    fun doesNotIncludeRawNotificationTextInThePersistedRecord() {
        val record = BankNotificationCapture.parse(
            packageName = "com.movilred.subscriber",
            notificationKey = "private-message-key",
            title = "Transferencia enviada",
            text = "Enviaste $ 8.500 a Carlos Pérez. Tu saldo es 100.000",
            observedAt = 1_791_471_600_000,
        )!!

        val storedFields = record.toMap().values.joinToString(" ")
        assertTrue(storedFields.contains("MOVii"))
        assertTrue(!storedFields.contains("Tu saldo es"))
    }
}
