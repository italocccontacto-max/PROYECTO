package com.irrovicas.blockade.platform.foreground

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Tests de la logica pura de seleccion de evento en foreground.
 * No dependen de UsageStatsManager ni de un dispositivo Android:
 * cubren exactamente los casos que se acordaron con ChatGPT.
 */
class ForegroundEventSelectorTest {

    private val activityResumed = ForegroundEventSelector.ACTIVITY_RESUMED
    private val otherEventType = 99

    @Test
    fun `returns null when there are no events`() {
        val result = ForegroundEventSelector.selectForegroundPackage(emptyList())

        assertNull(result)
    }

    @Test
    fun `returns package of the last ACTIVITY_RESUMED event`() {
        val events = listOf(
            ForegroundEvent("com.app.one", activityResumed, timestamp = 1_000L),
            ForegroundEvent("com.app.two", activityResumed, timestamp = 2_000L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertEquals("com.app.two", result)
    }

    @Test
    fun `ignores events that are not ACTIVITY_RESUMED`() {
        val events = listOf(
            ForegroundEvent("com.app.one", activityResumed, timestamp = 1_000L),
            ForegroundEvent("com.app.two", otherEventType, timestamp = 5_000L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertEquals("com.app.one", result)
    }

    @Test
    fun `handles multiple app switches and keeps the most recent one`() {
        val events = listOf(
            ForegroundEvent("com.app.a", activityResumed, timestamp = 1_000L),
            ForegroundEvent("com.app.b", otherEventType, timestamp = 1_500L),
            ForegroundEvent("com.app.b", activityResumed, timestamp = 2_000L),
            ForegroundEvent("com.app.c", activityResumed, timestamp = 3_000L),
            ForegroundEvent("com.app.c", otherEventType, timestamp = 3_500L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertEquals("com.app.c", result)
    }

    @Test
    fun `returns null when only non-resumed events are present`() {
        val events = listOf(
            ForegroundEvent("com.app.one", otherEventType, timestamp = 1_000L),
            ForegroundEvent("com.app.two", otherEventType, timestamp = 2_000L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertNull(result)
    }
}
