defmodule BeaconAssistantWeb.ChatLive do
  use BeaconAssistantWeb, :live_view

  alias BeaconAssistant.{Chatbot, Conversations}

  @impl true
  def mount(_params, session, socket) do
    chat_session_id = chat_session_id(session)
    exchanges = load_exchanges(chat_session_id)

    socket =
      assign(socket,
        page_title: "Beacon Support Assistant",
        chat_session_id: chat_session_id,
        exchanges: exchanges,
        loading: false,
        error: nil,
        form: to_form(%{"question" => ""}, as: :chat)
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"chat" => %{"question" => question}}, socket) do
    question = String.trim(question)

    cond do
      question == "" ->
        {:noreply, assign(socket, error: "Enter a question before sending.")}

      socket.assigns.loading ->
        {:noreply, socket}

      true ->
        socket =
          socket
          |> assign(loading: true, error: nil)
          |> ask_and_assign(question)

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto flex min-h-screen max-w-3xl flex-col px-6 py-10">
      <p class="text-sm font-semibold uppercase tracking-wide text-base-content/60">Beacon</p>

      <h1 class="mt-2 text-3xl font-semibold tracking-normal">
        Beacon Support Assistant
      </h1>

      <p class="mt-4 text-base leading-7 text-base-content/70">
        Ask a support question. Answers are generated from the local Markdown knowledge base.
      </p>

      <section
        id="chat-log"
        class="mt-8 flex min-h-96 flex-1 flex-col gap-4 rounded-lg border border-base-300 bg-base-100 p-4"
      >
        <p :if={@exchanges == []} class="py-16 text-center text-sm text-base-content/60">
          No messages yet.
        </p>

        <article :for={exchange <- @exchanges} class="space-y-3">
          <div class="rounded-lg bg-base-200 p-4">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/55">You</p>
            <p class="mt-1 text-sm leading-6">{exchange.question}</p>
          </div>

          <div class="rounded-lg border border-base-300 p-4">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/55">
              Assistant
            </p>
            <p class="mt-1 whitespace-pre-wrap text-sm leading-6">{exchange.answer}</p>
            <p :if={exchange.sources != []} class="mt-3 text-xs text-base-content/55">
              Sources: {Enum.join(exchange.sources, ", ")}
            </p>
          </div>
        </article>
      </section>

      <p :if={@error} class="mt-4 rounded-md bg-error/10 p-3 text-sm text-error">{@error}</p>

      <.form for={@form} phx-submit="send" class="mt-4 flex gap-3">
        <input
          id="question"
          name={@form[:question].name}
          value={@form[:question].value}
          type="text"
          placeholder="Ask about billing, 2FA, plans..."
          disabled={@loading}
          class="input input-bordered min-w-0 flex-1"
        />
        <button type="submit" class="btn btn-primary shrink-0" disabled={@loading}>
          <span :if={!@loading}>Send</span>
          <span :if={@loading}>Asking...</span>
        </button>
      </.form>
    </main>
    """
  end

  defp ask_and_assign(socket, question) do
    case Chatbot.ask(question, chat_session_id: socket.assigns.chat_session_id) do
      {:ok, exchange} ->
        assign(socket,
          exchanges: socket.assigns.exchanges ++ [exchange],
          loading: false,
          form: to_form(%{"question" => ""}, as: :chat)
        )

      {:error, :empty_question} ->
        assign(socket, loading: false, error: "Enter a question before sending.")
    end
  end

  defp chat_session_id(session) do
    Map.get(session, "chat_session_id") || Map.get(session, :chat_session_id) ||
      Ecto.UUID.generate()
  end

  defp load_exchanges(chat_session_id) do
    case Conversations.get_or_create_session(chat_session_id) do
      {:ok, session} -> Conversations.list_exchanges_for_session(session.id)
      {:error, _reason} -> []
    end
  end
end
