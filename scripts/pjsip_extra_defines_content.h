/*
 * PJSIP EXTRA DEFINES CONFIGURATION FILE
 *
 * Este ficheiro pode ser usado para adicionar definições de pré-processador
 * específicas para a sua compilação do PJSIP, que não estão em config_site.h.
 * Por exemplo: #define PJMEDIA_HAS_G729_CODEC 1
 */

// Adicione aqui quaisquer definições PJSIP adicionais necessárias para a sua compilação.
// Exemplo: #define PJ_CUSTOM_SETTING_ENABLED 1

// Fallback para PJMEDIA_AUD_MAX_DEVS caso não seja definido noutro lugar.
// O valor padrão no PJSIP é geralmente 4.
#ifndef PJMEDIA_AUD_MAX_DEVS
#define PJMEDIA_AUD_MAX_DEVS 4
#endif
