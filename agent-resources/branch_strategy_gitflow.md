# Branch Strategy — GitFlow

Questo documento definisce le regole da seguire per la gestione dei branch nella repository.

La strategia adottata è **GitFlow**, con:

- `master` come branch di produzione;
- `dev` come branch di sviluppo;
- branch di feature creati a partire da `dev`;
- branch di release creati a partire da `dev` e nominati con versione, ad esempio `v.1.0.1`.

---

## Branch principali

### `master`

Il branch `master` rappresenta sempre la **produzione**.

Regole:

- deve contenere solo codice stabile e pronto per il rilascio;
- non si lavora mai direttamente su `master`;
- ogni modifica su `master` deve arrivare tramite merge da un branch di release;
- ogni merge su `master` deve corrispondere a una versione rilasciata;
- dopo il merge su `master`, creare un tag Git con la stessa versione della release.

Esempio:

```bash
git checkout master
git merge v.1.0.1
git tag v.1.0.1
git push origin master --tags
```

---

### `dev`

Il branch `dev` rappresenta l’ambiente di sviluppo principale.

Regole:

- tutte le feature partono da `dev`;
- tutte le feature completate vengono mergiate in `dev`;
- `dev` può contenere codice non ancora rilasciato in produzione;
- `dev` deve comunque rimanere il più stabile possibile;
- prima di creare una release, `dev` deve essere testato e allineato.

Esempio:

```bash
git checkout dev
git pull origin dev
```

---

## Branch di feature

I branch di feature vengono creati a partire da `dev`.

Naming convention:

```text
nome-feature
```

Esempi:

```text
chat-interface
llm-client
markdown-knowledge-base
failure-handling
conversation-persistence
```

Regole:

- il nome deve descrivere chiaramente la feature;
- usare lettere minuscole;
- usare trattini `-` al posto degli spazi;
- evitare nomi generici come `update`, `fix`, `changes`, `test`;
- ogni branch deve contenere una singola feature o modifica coerente;
- non lavorare direttamente su `dev`;
- prima del merge, eseguire format e test.

Creazione di una feature:

```bash
git checkout dev
git pull origin dev
git checkout -b chat-interface
```

Durante lo sviluppo:

```bash
git status
git add .
git commit -m "Add chat interface"
git push origin chat-interface
```

Merge della feature in `dev`:

```bash
git checkout dev
git pull origin dev
git merge chat-interface
git push origin dev
```

Dopo il merge, il branch di feature può essere eliminato:

```bash
git branch -d chat-interface
git push origin --delete chat-interface
```

---

## Branch di release

I branch di release vengono creati a partire da `dev` quando si vuole preparare una nuova versione da rilasciare in produzione.

Naming convention:

```text
v.X.Y.Z
```

Esempi:

```text
v.1.0.0
v.1.0.1
v.1.1.0
```

Regole:

- il branch di release parte sempre da `dev`;
- su un branch di release si fanno solo bugfix, rifiniture, aggiornamenti README/DECISIONS e preparazione al deploy;
- non aggiungere nuove feature su un branch di release;
- quando la release è stabile, viene mergiata in `master`;
- dopo il merge in `master`, la release deve essere mergiata anche in `dev`, così eventuali fix fatti in release non vengono persi.

Creazione di una release:

```bash
git checkout dev
git pull origin dev
git checkout -b v.1.0.1
git push origin v.1.0.1
```

Merge in produzione:

```bash
git checkout master
git pull origin master
git merge v.1.0.1
git tag v.1.0.1
git push origin master --tags
```

Riallineamento di `dev`:

```bash
git checkout dev
git pull origin dev
git merge v.1.0.1
git push origin dev
```

---

## Hotfix

Gli hotfix servono per correggere rapidamente problemi presenti in produzione.

Naming convention consigliata:

```text
hotfix-descrizione-breve
```

Esempi:

```text
hotfix-llm-timeout
hotfix-env-config
hotfix-chat-crash
```

Regole:

- il branch hotfix parte da `master`;
- contiene solo la correzione urgente;
- dopo la verifica, viene mergiato in `master`;
- dopo il merge in `master`, deve essere mergiato anche in `dev`;
- se necessario, creare un nuovo tag di patch release.

Creazione hotfix:

```bash
git checkout master
git pull origin master
git checkout -b hotfix-llm-timeout
```

Merge hotfix in produzione:

```bash
git checkout master
git merge hotfix-llm-timeout
git tag v.1.0.2
git push origin master --tags
```

Riallineamento di `dev`:

```bash
git checkout dev
git pull origin dev
git merge hotfix-llm-timeout
git push origin dev
```

---

## Regole per i commit

I commit devono essere piccoli, leggibili e collegati a una modifica chiara.

Esempi buoni:

```text
Add chat exchange persistence
Load markdown knowledge base
Handle LLM timeout gracefully
Add release documentation
Fix empty model response handling
```

Esempi da evitare:

```text
update
fix
changes
wip
stuff
final
```

Regole:

- preferire commit piccoli e frequenti;
- ogni commit deve rappresentare un passaggio comprensibile;
- non committare file temporanei, log locali, chiavi API o `.env`;
- prima di committare, controllare sempre il diff.

Comandi utili:

```bash
git status
git diff
git add .
git commit -m "Add grounded prompt builder"
```

---

## Pull request e merge

Ogni branch di feature o release dovrebbe essere mergiato tramite Pull Request, quando possibile.

Checklist prima del merge:

- il codice compila;
- i test passano;
- il format è stato eseguito;
- non sono presenti chiavi, token o file `.env`;
- la feature è coerente con lo scope del branch;
- la documentazione è aggiornata se necessario;
- non sono state introdotte feature non richieste.

Per progetti Elixir/Phoenix, prima del merge eseguire:

```bash
mix format
mix test
```

Se presente Credo:

```bash
mix credo
```

---

## Regole specifiche per questo progetto

Per il progetto Beacon Support Assistant:

- `master` è produzione;
- `dev` è sviluppo;
- le feature devono partire da `dev`;
- la logica LLM e grounding non deve essere implementata direttamente nella LiveView;
- ogni feature deve mantenere il progetto funzionante end-to-end;
- non introdurre vector database, embeddings, auth o admin panel senza decisione esplicita;
- ogni modifica importante deve essere riflessa in `README.md` o `DECISIONS.md` se cambia architettura, setup o comportamento.

Branch feature consigliati:

```text
project-setup
chat-persistence
chat-liveview
knowledge-base-loader
llm-client
grounded-answering
failure-handling
sources-display
deployment-config
documentation
```

---

## Flusso standard consigliato

### 1. Sviluppo feature

```bash
git checkout dev
git pull origin dev
git checkout -b nome-feature
```

Sviluppare, testare e committare:

```bash
mix format
mix test
git status
git add .
git commit -m "Add nome feature"
git push origin nome-feature
```

Aprire Pull Request verso `dev`.

---

### 2. Preparazione release

```bash
git checkout dev
git pull origin dev
git checkout -b v.1.0.1
```

Fare solo fix finali, documentazione e verifiche.

Poi merge in `master`:

```bash
git checkout master
git merge v.1.0.1
git tag v.1.0.1
git push origin master --tags
```

Infine riallineare `dev`:

```bash
git checkout dev
git merge v.1.0.1
git push origin dev
```

---

## Cose da evitare

Non fare:

```text
- commit diretti su master
- commit diretti su dev, salvo casi eccezionali
- branch feature creati da master
- nuove feature dentro branch di release
- release senza tag
- hotfix mergiati solo in master e non in dev
- branch con nomi vaghi
- commit con messaggi non descrittivi
- merge senza aver eseguito test e format
```

---

## Sintesi

La strategia da seguire è:

```text
master = produzione
dev = sviluppo
nome-feature = sviluppo di una singola feature
v.X.Y.Z = preparazione release
hotfix-descrizione = correzione urgente da produzione
```

Flusso principale:

```text
feature branch → dev → release branch → master
                         ↓
                         dev
```

Flusso hotfix:

```text
master → hotfix → master
              ↓
              dev
```

L’obiettivo è mantenere `master` sempre stabile, `dev` come base di integrazione e ogni modifica isolata in branch piccoli, leggibili e facili da revisionare.
