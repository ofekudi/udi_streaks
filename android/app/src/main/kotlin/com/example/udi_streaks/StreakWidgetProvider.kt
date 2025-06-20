package com.example.udi_streaks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.app.PendingIntent
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Implementation of App Widget functionality for streak display.
 */
class StreakWidgetProvider : AppWidgetProvider() {
    
    companion object {
        private const val TAG = "StreakWidgetProvider"
    }
    
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d(TAG, "onUpdate called with ${appWidgetIds.size} widgets")
        // There may be multiple widgets active, so update all of them
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        Log.d(TAG, "onReceive called with action: ${intent.action}")
        
        if (intent.action == "es.antonborri.home_widget.action.UPDATE_WIDGET") {
            Log.d(TAG, "Received widget update request")
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, StreakWidgetProvider::class.java)
            )
            Log.d(TAG, "Updating ${appWidgetIds.size} widgets")
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        try {
            // Get widget data from SharedPreferences
            val widgetData = HomeWidgetPlugin.getData(context)
            
            val completed = widgetData.getInt("completed", 0)
            val total = widgetData.getInt("total", 0)
            
            val streakText = "$completed/$total"
            Log.d(TAG, "Widget #$appWidgetId updating with: $streakText")
            
            // Construct the RemoteViews object
            val views = RemoteViews(context.packageName, R.layout.widget_streak)
            views.setTextViewText(R.id.streak_count, streakText)
            
            // Update progress bar visual
            val maxValue = if (total == 0) 1 else total
            val progressValue = if (completed > total) total else completed
            views.setProgressBar(R.id.streak_progress, maxValue, progressValue, false)
            
            // Create intent to launch the app when widget is tapped
            val intent = Intent(context, MainActivity::class.java)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            
            // Instruct the widget manager to update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
            Log.d(TAG, "Widget #$appWidgetId updated successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error updating widget #$appWidgetId", e)
            // Fallback: show error state
            val views = RemoteViews(context.packageName, R.layout.widget_streak)
            views.setTextViewText(R.id.streak_count, "0/0")
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
    
    override fun onEnabled(context: Context) {
        Log.d(TAG, "Widget enabled")
        super.onEnabled(context)
    }
    
    override fun onDisabled(context: Context) {
        Log.d(TAG, "Widget disabled")
        super.onDisabled(context)
    }
} 