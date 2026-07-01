# Error Handling E2E Test Runbook

Questo runbook descrive le verifiche manuali end-to-end per controllare che il gestore degli errori funzioni nella UI e che la LiveView non vada in crash.

## Messaggi attesi

- Offline browser: `You appear to be offline. Connect to the internet before sending a request.`
- Timeout modello: `The model is taking too long to respond. Please try again.`
- Errore critico: `Something went wrong. Please try again later.`
- Knowledge base non disponibile o vuota: `I'm not able to retrieve that information from the available knowledge base.`

## Setup comune

1. Apri un terminale nella root del progetto:

   ```sh
   cd /Users/andreaioele/Learn/Odda/Indigo/challenge/beacon-assistant
   ```

2. Avvia PostgreSQL locale:

   ```sh
   docker compose up -d db
   ```

3. Prepara database e asset, se non sono gia pronti:

   ```sh
   mix ecto.setup
   ```

4. Crea un fake provider LLM riutilizzabile per simulare risposte controllate:

   ```sh
   cat > /tmp/beacon_fake_llm.py <<'PY'
   import json
   import os
   import sys
   import time
   from http.server import BaseHTTPRequestHandler, HTTPServer

   mode = os.environ.get("FAKE_LLM_MODE", "ok")
   port = int(sys.argv[1])

   class Handler(BaseHTTPRequestHandler):
       def do_POST(self):
           length = int(self.headers.get("content-length", "0"))
           if length:
               self.rfile.read(length)

           if mode == "slow":
               time.sleep(60)
               return

           if mode == "error":
               self.send_response(500)
               self.send_header("content-type", "application/json")
               self.end_headers()
               self.wfile.write(b'{"error":"forced e2e error"}')
               return

           if mode == "malformed":
               self.send_response(200)
               self.send_header("content-type", "application/json")
               self.end_headers()
               self.wfile.write(b'{"done":true}')
               return

           body = {
               "response": json.dumps({
                   "answer": "E2E fake answer.",
                   "sources": []
               })
           }
           payload = json.dumps(body).encode("utf-8")
           self.send_response(200)
           self.send_header("content-type", "application/json")
           self.send_header("content-length", str(len(payload)))
           self.end_headers()
           self.wfile.write(payload)

       def log_message(self, format, *args):
           return

   HTTPServer(("127.0.0.1", port), Handler).serve_forever()
   PY
   ```

5. Per ogni scenario sotto, usa una finestra browser pulita o ricarica `http://localhost:4000` prima del test.

6. Per fermare l'app o un fake provider, premi `Ctrl+C` nel terminale in cui sta girando.

## 1 - Test baseline: app funzionante con provider fake

1. In un terminale, avvia il fake provider in modalita successo:

   ```sh
   FAKE_LLM_MODE=ok python3 /tmp/beacon_fake_llm.py 11500
   ```

2. In un secondo terminale, avvia Phoenix puntando al fake provider:

   ```sh
   LLM_PROVIDER=ollama \
   OLLAMA_GENERATE_URL=http://127.0.0.1:11500/api/generate \
   OLLAMA_MODEL=e2e-fake \
   OLLAMA_TIMEOUT_MS=5000 \
   mix phx.server
   ```

3. Apri `http://localhost:4000`.

4. Invia una domanda, per esempio `How does billing work?`.

5. Verifica che nella UI compaia la risposta `E2E fake answer.` e che la pagina resti interattiva.

## 2 - Test modalita offline browser

1. Avvia l'app come nello scenario baseline.

2. Apri `http://localhost:4000`.

3. Metti il browser offline. Opzioni valide:
   - scollega il Wi-Fi;
   - oppure usa Chrome DevTools, tab `Network`, preset `Offline`.

4. Verifica che nella UI compaia:

   ```text
   You appear to be offline. Connect to the internet before sending a request.
   ```

5. Verifica che campo di input e bottone `Send` siano disabilitati.

6. Prova a inviare una domanda. Verifica che non parta nessuna nuova richiesta e che non venga aggiunto un messaggio dell'assistente.

7. Riporta il browser online.

8. Verifica che il messaggio offline scompaia e che il form torni utilizzabile.

9. Invia una domanda e verifica che la risposta arrivi normalmente.

## 3 - Test timeout del modello

1. Ferma eventuali fake provider ancora attivi.

2. Avvia il fake provider in modalita lenta:

   ```sh
   FAKE_LLM_MODE=slow python3 /tmp/beacon_fake_llm.py 11501
   ```

3. Avvia Phoenix con timeout breve:

   ```sh
   LLM_PROVIDER=ollama \
   OLLAMA_GENERATE_URL=http://127.0.0.1:11501/api/generate \
   OLLAMA_MODEL=e2e-fake \
   OLLAMA_TIMEOUT_MS=1000 \
   mix phx.server
   ```

4. Apri `http://localhost:4000`.

5. Invia una domanda.

6. Verifica che nella chat compaia:

   ```text
   The model is taking too long to respond. Please try again.
   ```

7. Verifica che la LiveView non crashi: il form deve tornare abilitato e deve essere possibile inviare una nuova domanda dopo aver riavviato l'app con un provider funzionante.

## 4 - Test errore critico: provider HTTP 500

1. Ferma app e fake provider eventualmente attivi.

2. Avvia il fake provider in modalita errore HTTP:

   ```sh
   FAKE_LLM_MODE=error python3 /tmp/beacon_fake_llm.py 11502
   ```

3. Avvia Phoenix:

   ```sh
   LLM_PROVIDER=ollama \
   OLLAMA_GENERATE_URL=http://127.0.0.1:11502/api/generate \
   OLLAMA_MODEL=e2e-fake \
   OLLAMA_TIMEOUT_MS=5000 \
   mix phx.server
   ```

4. Apri `http://localhost:4000`.

5. Invia una domanda.

6. Verifica che nella chat compaia:

   ```text
   Something went wrong. Please try again later.
   ```

7. Verifica che non siano visibili stack trace, payload, endpoint, API key o dettagli tecnici del provider.

## 5 - Test errore critico: risposta provider malformata

1. Ferma app e fake provider eventualmente attivi.

2. Avvia il fake provider in modalita risposta malformata:

   ```sh
   FAKE_LLM_MODE=malformed python3 /tmp/beacon_fake_llm.py 11503
   ```

3. Avvia Phoenix:

   ```sh
   LLM_PROVIDER=ollama \
   OLLAMA_GENERATE_URL=http://127.0.0.1:11503/api/generate \
   OLLAMA_MODEL=e2e-fake \
   OLLAMA_TIMEOUT_MS=5000 \
   mix phx.server
   ```

4. Apri `http://localhost:4000`.

5. Invia una domanda.

6. Verifica che nella chat compaia:

   ```text
   Something went wrong. Please try again later.
   ```

7. Verifica che la pagina resti utilizzabile e non mostri errori tecnici.

## 6 - Test knowledge base vuota

1. Ferma app e fake provider eventualmente attivi.

2. Crea una directory knowledge base vuota:

   ```sh
   rm -rf /tmp/beacon-empty-kb
   mkdir -p /tmp/beacon-empty-kb
   ```

3. Avvia Phoenix usando quella directory:

   ```sh
   KNOWLEDGE_BASE_DIR=/tmp/beacon-empty-kb \
   LLM_PROVIDER=ollama \
   OLLAMA_GENERATE_URL=http://127.0.0.1:11500/api/generate \
   OLLAMA_MODEL=e2e-fake \
   OLLAMA_TIMEOUT_MS=5000 \
   mix phx.server
   ```

4. Apri `http://localhost:4000`.

5. Invia una domanda.

6. Verifica che nella chat compaia:

   ```text
   I'm not able to retrieve that information from the available knowledge base.
   ```

7. Verifica che non venga mostrata nessuna source e che la UI resti funzionante.

## 7 - Test errore di persistenza dopo caricamento pagina

1. Ferma app e fake provider eventualmente attivi.

2. Avvia il fake provider in modalita successo:

   ```sh
   FAKE_LLM_MODE=ok python3 /tmp/beacon_fake_llm.py 11500
   ```

3. Assicurati che PostgreSQL sia attivo:

   ```sh
   docker compose up -d db
   ```

4. Avvia Phoenix:

   ```sh
   LLM_PROVIDER=ollama \
   OLLAMA_GENERATE_URL=http://127.0.0.1:11500/api/generate \
   OLLAMA_MODEL=e2e-fake \
   OLLAMA_TIMEOUT_MS=5000 \
   mix phx.server
   ```

5. Apri `http://localhost:4000` e attendi che la pagina sia caricata.

6. In un altro terminale, ferma solo PostgreSQL:

   ```sh
   docker compose stop db
   ```

7. Torna al browser e invia una domanda.

8. Verifica che la LiveView non crashi e che compaia comunque `E2E fake answer.`.

9. Verifica nei log Phoenix che ci sia un errore di persistenza, senza che venga esposto nella UI.

10. Riavvia PostgreSQL:

    ```sh
    docker compose up -d db
    ```

## 8 - Test regressione automatica

1. Esegui la suite automatica:

   ```sh
   mix test
   ```

2. Verifica che tutti i test passino.

3. Se l'ambiente Codex/sandbox blocca Mix con `failed to acquire filesystem lock using TCP, reason: :eperm`, rilancia `mix test` fuori sandbox.

## Checklist finale

1. Offline browser blocca il submit e mostra solo il messaggio offline.
2. Timeout modello mostra il messaggio timeout.
3. HTTP 500 provider mostra il messaggio critico.
4. Risposta provider malformata mostra il messaggio critico.
5. Knowledge base vuota mostra il fallback knowledge base.
6. Errore di persistenza non fa crashare la LiveView.
7. Nessuna UI espone stack trace, payload, API key o dettagli tecnici.
8. Dopo ogni errore il form torna utilizzabile, salvo quando il browser resta offline.
9. `mix test` passa.
