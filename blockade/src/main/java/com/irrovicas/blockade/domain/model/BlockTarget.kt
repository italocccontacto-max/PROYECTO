package com.irrovicas.blockade.domain.model

/**
 * Identifica qué recurso intenta restringir una política.
 *
 * El dominio no conoce cómo se realiza técnicamente el bloqueo.
 * Solo describe el objetivo.
 */
sealed interface BlockTarget {

    /**
     * Aplicación Android identificada mediante packageName.
     */
    data class Application(
        val packageName: String,
    ) : BlockTarget

    /**
     * Dominio web completo.
     *
     * Ejemplo:
     * example.com
     */
    data class WebDomain(
        val domain: String,
    ) : BlockTarget

    /**
     * Palabra clave encontrada en una URL o contexto web.
     *
     * matchingMode determina cómo debe interpretarse.
     */
    data class Keyword(
        val value: String,
        val matchingMode: KeywordMatchingMode,
    ) : BlockTarget

    /**
     * Contenido específico dentro de una aplicación.
     *
     * Ejemplo:
     * Instagram Reels.
     */
    data class AppContent(
        val packageName: String,
        val contentType: AppContentType,
    ) : BlockTarget
}

enum class KeywordMatchingMode {
    DOMAIN,
    URL_ANYWHERE,
}

enum class AppContentType {
    INSTAGRAM_REELS,
    INSTAGRAM_STORIES,
    YOUTUBE_SHORTS,
    SNAPCHAT_STORIES,
    SNAPCHAT_SPOTLIGHT,
    WHATSAPP_CHANNELS,
    WHATSAPP_STATUS,
}
