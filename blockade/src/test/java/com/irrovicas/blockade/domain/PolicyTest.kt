package com.irrovicas.blockade.domain

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PolicyTest {
    @Test
    fun policy_defaults_to_non_strict() {
        val policy = BlockadePolicy("demo", "Demo", enabled = true)
        assertTrue(policy.enabled)
        assertFalse(policy.strict)
    }
}
