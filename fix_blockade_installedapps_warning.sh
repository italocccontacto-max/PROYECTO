#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# fix_blockade_installedapps_warning.sh
#
# Elimina la unica safe call innecesaria que quedo como warning
# desde Fase 3 en AndroidInstalledAppsProvider.kt:36
# ("Unnecessary safe call on a non-null receiver of type
# 'CharSequence'"), tal como lo indico ChatGPT. Commit separado
# de Fase 4, tal como pidio explicitamente.
#
# VERIFICADO CONTRA EL REPO REAL (commit 181c789, rama main).
# El bloque real es:
#
#   val label =
#       resolveInfo.loadLabel(packageManager)
#           ?.toString()
#           ?.trim()
#           .orEmpty()
#
# loadLabel() devuelve CharSequence no nulo (por eso el warning
# especifico en esa linea), y toString()/trim() tampoco devuelven
# nulo nunca en la practica, asi que .orEmpty() tampoco aporta
# nada real.
#
# Cambio minimo aplicado con sed linea por linea (no se toca nada
# mas del archivo, comportamiento identico, cero cambios
# funcionales):
#   - se quita el "?" de "?.toString()"
#   - se quita el "?" de "?.trim()"
#   - se borra la linea ".orEmpty()"
#
# Nota: mantengo el chain multilinea (una llamada por linea) en
# vez de aplastarlo a una sola linea como sugirio ChatGPT, porque
# es el estilo que usa el resto del archivo/repo. El resultado es
# equivalente, solo mas consistente con el resto del codigo.
#
# Ya probado contra una copia real del archivo antes de escribir
# este script: el diff aplica limpio y el resto del archivo queda
# intacto.
# ============================================================

REPO_ROOT="$(pwd)"
FILE="$REPO_ROOT/blockade/src/main/java/com/irrovicas/blockade/platform/apps/AndroidInstalledAppsProvider.kt"

echo "== Validando precondiciones =="

if [ ! -f "$FILE" ]; then
  echo "ERROR: no se encontro $FILE"
  echo "       Corre este script desde la raiz del repo (PROYECTO/)."
  exit 1
fi

if ! grep -Fxq '                        ?.toString()' "$FILE"; then
  echo "ERROR: no se encontro la linea '?.toString()' con la indentacion esperada."
  echo "       El archivo cambio respecto a lo verificado - abortando en vez de adivinar."
  exit 1
fi

if ! grep -Fxq '                        ?.trim()' "$FILE"; then
  echo "ERROR: no se encontro la linea '?.trim()' con la indentacion esperada."
  exit 1
fi

if ! grep -Fxq '                        .orEmpty()' "$FILE"; then
  echo "ERROR: no se encontro la linea '.orEmpty()' con la indentacion esperada."
  exit 1
fi

echo "OK: las 3 lineas esperadas estan presentes tal cual se verificaron contra el repo real."

echo "== Aplicando el fix =="
sed -i \
  -e 's/^                        ?\.toString()$/                        .toString()/' \
  -e 's/^                        ?\.trim()$/                        .trim()/' \
  -e '/^                        \.orEmpty()$/d' \
  "$FILE"

echo "== Resultado (funcion completa) =="
cat "$FILE"

echo ""
echo "== Deteniendo el daemon de Gradle antes de compilar (memoria limitada en Codespaces) =="
cd "$REPO_ROOT"
./gradlew --stop

echo ""
echo "== Corriendo ./gradlew :blockade:test =="
./gradlew :blockade:test

echo ""
echo "== Estado en git =="
git add -A
git status --short
echo ""
echo "== Diff exacto =="
git diff --cached -- blockade/src/main/java/com/irrovicas/blockade/platform/apps/AndroidInstalledAppsProvider.kt

cat << 'MSG'

============================================================
Warning corregido en AndroidInstalledAppsProvider.kt.

Fijate en el output de arriba si el build ya no reporta el
warning de "Unnecessary safe call" (antes salia junto con
BUILD SUCCESSFUL, no rompia el build, pero deberia desaparecer
del output ahora).

Para commitear y subir (commit separado, tal como pidio ChatGPT):

  git commit -m "fix(blockade): remove redundant safe call in app label"
  git push origin main

Con esto quedan cerrados los pendientes cosmeticos de Fase 3.
Fase 4 (ForegroundAppProvider + UsageStatsManager) queda para el
siguiente script, como lo planteo ChatGPT.
============================================================
MSG
