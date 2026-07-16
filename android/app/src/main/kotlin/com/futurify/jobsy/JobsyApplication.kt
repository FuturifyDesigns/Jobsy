package com.futurify.jobsy

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.util.Log

/**
 * Runs before Flutter / MainActivity. Creates the FCM channel with [R.raw.soundreality_notification].
 * Keep in sync with push_notification_service.dart, AndroidManifest, and Edge Function.
 */
class JobsyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        createJobsyNotificationChannel()
    }

    private fun createJobsyNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = getSystemService(NotificationManager::class.java) ?: return

        val soundUri = Uri.parse(
            "${ContentResolver.SCHEME_ANDROID_RESOURCE}://${packageName}/${R.raw.soundreality_notification}",
        )

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            JOBSY_NOTIFICATION_CHANNEL_ID,
            "Jobsy Notifications",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Job updates, messages, and activity from Jobsy"
            setSound(soundUri, attrs)
            enableVibration(true)
            setShowBadge(true)
        }

        nm.createNotificationChannel(channel)
        Log.i("JobsyApplication", "Channel $JOBSY_NOTIFICATION_CHANNEL_ID + custom sound")
    }

    companion object {
        const val JOBSY_NOTIFICATION_CHANNEL_ID = "jobsy_default_v4"
    }
}
