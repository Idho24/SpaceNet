package com.example.spacenet

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "spacenet_service", "Informasi layanan SpaceNet", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Perbaikan jaringan dan gangguan massal" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
