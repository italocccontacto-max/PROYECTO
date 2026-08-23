package com.irrovicas.blockade.accessibility

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class BlockadeAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Enforcement engine placeholder.
        // Future phases will evaluate active policies and browser/content rules here.
    }

    override fun onInterrupt() = Unit
}
