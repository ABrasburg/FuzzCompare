# FuzzCompare

Scripts para preparar, ejecutar y comparar campañas de fuzzing con **AFL++** y **libFuzzer** sobre el mismo objetivo, con una medición de cobertura común a ambos motores.

Es la primera versión del prototipo descrito en la sección 7 del trabajo final *Evaluación comparativa de fuzzers guiados por cobertura para detectar errores en un parser* (Maestría en Seguridad Informática, Sistemas Operativos, 2026). El objetivo usado fue el parser JSON de [json-c](https://github.com/json-c/json-c) (commit `0389cc85ce058073430938f8f4824986caa4d663`) con su harness `fuzz/tokener_parse_ex_fuzzer.cc`.

## Contenido

| Archivo | Qué hace |
|---|---|
| `campanas.sh` | Prepara una copia independiente del corpus inicial para cada campaña, lanza las campañas de ambos motores en forma intercalada con un núcleo asignado (`taskset -c 0`), toma instantáneas del corpus cada 60 s y registra el RSS periódicamente. |
| `cobertura.sh` | Compila json-c con cobertura de código fuente de Clang, reproduce cada corpus final y cada instantánea con un mismo binario (`tools/replay`) y extrae regiones, líneas, ramas y funciones con `llvm-cov`. |
| `submuestreo2.sh` | Toma submuestras aleatorias (50 a 800 entradas, tres repeticiones) de los diez corpus finales y mide su cobertura, para comparar los motores a igual tamaño de corpus. |
| `submuestreo.sh` | Versión anterior del submuestreo, sobre una sola campaña por motor. |
| `tools/replay_main.c` | `main` mínimo que invoca `LLVMFuzzerTestOneInput` sobre cada archivo de un directorio; se enlaza con el harness para la medición común. |
| `seeds/` | Corpus inicial (tres semillas) y sus sumas de verificación. |
| `results/` | Resultados de cobertura de la corrida final (`total.txt`, `curvas.txt`, `submuestreo2/sub.tsv`). |

## Requisitos

Probado en Ubuntu 26.04.1 LTS (VirtualBox, 2 vCPU, 4 GiB, sin swap) con Clang/LLVM 21.1.8, AFL++ 4.33c (LLVM-PCGUARD), CMake 4.2.3 y Git 2.53.0.

Antes de correr las campañas:

```bash
echo core | sudo tee /proc/sys/kernel/core_pattern   # evita que Apport intercepte los volcados
```

## Uso

```bash
bash campanas.sh        # 5 campañas por motor, 300 s cada una, intercaladas
bash cobertura.sh       # medición común de corpus finales e instantáneas
bash submuestreo2.sh    # comparación a igual tamaño de corpus
```

Las rutas asumen el laboratorio en `~/fuzzing-lab`, con json-c clonado en `~/fuzzing-lab/src/json-c` y compilado según los comandos del Anexo A del trabajo.

## Configuración usada

| Parámetro | libFuzzer | AFL++ |
|---|---|---|
| Optimización | `-O1` | `-O1` |
| Sanitizers | ASan + UBSan, `-fno-sanitize-recover=all` | ASan + UBSan, `-fno-sanitize-recover=all` |
| Tamaño máximo de entrada | `-max_len=4096` | `-G 4096` |
| Timeout por ejecución | `-timeout=10` | `-t 10000` |
| Memoria | `-rss_limit_mb=0` | `-m none` |
| Presupuesto | `-max_total_time=300` | `-V 300` |

Nota: en libFuzzer, `-ignore_crashes` e `-ignore_timeouts` solo tienen efecto con `-fork`; sin ese modo, la campaña se detiene en el primer fallo.

## Pendiente

- Agrupar posibles duplicados de fallos por señal y pila de llamadas.
- Generar un informe automático con versiones, configuración, métricas por campaña y advertencias sobre condiciones no equivalentes entre motores.
