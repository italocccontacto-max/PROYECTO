package com.irrovicas.blockade.platform.foreground

/**
 * Abstraccion minima sobre la hora actual, para que la logica de
 * ForegroundAppProvider no dependa directamente de
 * System.currentTimeMillis() y se pueda testear con un reloj falso.
 */
interface Clock {

    fun currentTimeMillis(): Long
}

class SystemClock : Clock {

    override fun currentTimeMillis(): Long = System.currentTimeMillis()
}
