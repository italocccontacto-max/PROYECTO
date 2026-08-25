package com.irrovicas.blockade.accessibility

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AccessibilityEventFilterTest {

    private val windowStateChanged =
        AccessibilityEventFilter.TYPE_WINDOW_STATE_CHANGED
    private val otherEventType = 2048 // typeWindowContentChanged real
    private val ownPackage = "com.irrovicas.blockade"

    @Test
    fun `returns the package on a window state change from another app`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = "com.instagram.android",
            ownPackageName = ownPackage,
        )

        assertEquals("com.instagram.android", result)
    }

    @Test
    fun `ignores events that are not a window state change`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = otherEventType,
            packageName = "com.instagram.android",
            ownPackageName = ownPackage,
        )

        assertNull(result)
    }

    @Test
    fun `ignores events with a null package name`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = null,
            ownPackageName = ownPackage,
        )

        assertNull(result)
    }

    @Test
    fun `ignores events with a blank package name`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = "   ",
            ownPackageName = ownPackage,
        )

        assertNull(result)
    }

    @Test
    fun `ignores events coming from BLOCKADE itself`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = ownPackage,
            ownPackageName = ownPackage,
        )

        assertNull(result)
    }
}
