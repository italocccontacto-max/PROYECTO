package com.irrovicas.blockade.domain.model

/**
 * Define qué aspecto del objetivo debe restringirse.
 */
enum class BlockAction {
    /**
     * Impide iniciar o continuar la aplicación/contenido.
     */
    LAUNCH,

    /**
     * Impide o silencia las notificaciones relacionadas.
     */
    NOTIFICATION,

    /**
     * Bloqueo completo.
     *
     * Es una forma semántica de indicar que todas las acciones
     * aplicables deben quedar restringidas.
     */
    FULL,
}
