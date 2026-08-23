package com.irrovicas.blockade.domain

/** Immutable contract for a device-restriction policy. */
data class BlockadePolicy(
    val id: String,
    val name: String,
    val enabled: Boolean,
    val strict: Boolean = false,
)
