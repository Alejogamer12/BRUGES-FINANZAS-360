package com.bruges.finanzas360

import android.app.Notification
import android.content.ComponentName
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel

object BankNotificationEvents {
    @Volatile
    var sink: EventChannel.EventSink? = null
}

class BankNotificationListenerService : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        // Android owns this bound service lifecycle and reconnects it while the
        // user's notification access remains enabled.
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        requestRebind(ComponentName(this, BankNotificationListenerService::class.java))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val enabledPackages = BankNotificationCapture.enabledPackages(this)
        if (sbn.packageName !in enabledPackages) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return

        // Raw text exists only in this callback's memory. Only conservative,
        // structured transaction fields enter the private durable queue.
        val record = BankNotificationCapture.parse(
            packageName = sbn.packageName,
            notificationKey = sbn.key,
            title = title,
            text = text,
            observedAt = sbn.postTime,
        ) ?: return
        BankNotificationCapture.enqueue(this, record)
        BankNotificationEvents.sink?.success(record.toMap())
    }
}
