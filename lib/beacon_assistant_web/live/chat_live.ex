defmodule BeaconAssistantWeb.ChatLive do
  use BeaconAssistantWeb, :live_view

  alias BeaconAssistant.{Chatbot, Conversations, ErrorHandling}
  require Logger

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
        active_stream_ref: nil,
        active_task_ref: nil,
        error: nil,
        client_online: true,
        form: to_form(%{"question" => ""}, as: :chat)
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"chat" => %{"question" => question}}, socket) do
    question = String.trim(question)

    cond do
      not socket.assigns.client_online ->
        {:noreply, assign(socket, error: ErrorHandling.offline_message())}

      question == "" ->
        {:noreply, assign(socket, error: "Enter a question before sending.")}

      socket.assigns.loading ->
        {:noreply, socket}

      true ->
        {:noreply, start_streaming_answer(socket, question)}
    end
  end

  @impl true
  def handle_event("network_status_changed", %{"online" => online}, socket)
      when is_boolean(online) do
    handle_network_status_changed(online, socket)
  end

  def handle_event("network_status_changed", %{online: online}, socket)
      when is_boolean(online) do
    handle_network_status_changed(online, socket)
  end

  @impl true
  def handle_info({:chat_stream_delta, stream_ref, delta}, socket) do
    if socket.assigns.active_stream_ref == stream_ref do
      {:noreply, update(socket, :exchanges, &append_pending_answer_delta(&1, stream_ref, delta))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_stream_done, stream_ref, exchange}, socket) do
    if socket.assigns.active_stream_ref == stream_ref do
      socket =
        socket
        |> assign(loading: false, active_stream_ref: nil, active_task_ref: nil)
        |> update(:exchanges, &replace_pending_exchange(&1, stream_ref, exchange))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_stream_failed, stream_ref, exchange}, socket) do
    if socket.assigns.active_stream_ref == stream_ref do
      socket =
        socket
        |> assign(loading: false, active_stream_ref: nil, active_task_ref: nil)
        |> update(:exchanges, &replace_pending_exchange(&1, stream_ref, exchange))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({task_ref, _result}, socket) do
    if task_ref == socket.assigns.active_task_ref do
      Process.demonitor(task_ref, [:flush])
    end

    {:noreply, socket}
  end

  def handle_info({:DOWN, task_ref, :process, _pid, reason}, socket) do
    if task_ref == socket.assigns.active_task_ref do
      Logger.error("chat_live stream task stopped reason=#{inspect(reason)}")

      exchange =
        failed_pending_exchange(
          socket.assigns.active_stream_ref,
          pending_question(socket.assigns.exchanges, socket.assigns.active_stream_ref)
        )

      socket =
        socket
        |> assign(loading: false, active_stream_ref: nil, active_task_ref: nil)
        |> update(:exchanges, &replace_pending_exchange(&1, exchange.id, exchange))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp handle_network_status_changed(online, socket) do
    error =
      cond do
        not online -> ErrorHandling.offline_message()
        socket.assigns.error == ErrorHandling.offline_message() -> nil
        true -> socket.assigns.error
      end

    {:noreply, assign(socket, client_online: online, error: error)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="chat-live"
      phx-hook="NetworkStatus"
      class="mx-auto flex min-h-screen max-w-3xl flex-col px-6 py-10"
    >
      <p class="text-sm font-semibold uppercase tracking-wide text-base-content/60">Beacon</p>

      <h1 class="mt-2 text-3xl font-semibold tracking-normal">
        Beacon Support Assistant
      </h1>

      <p class="mt-4 text-base leading-7 text-base-content/70">
        Ask a support question. Answers are generated from the local Markdown knowledge base.
      </p>

      <section
        id="chat-log"
        phx-hook="ChatAutoScroll"
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
            <p class="mt-1 whitespace-pre-wrap text-sm leading-6">
              <span :if={exchange_answer(exchange) != ""}>{exchange_answer(exchange)}</span>
              <span
                :if={pending_exchange?(exchange) && exchange_answer(exchange) == ""}
                class="text-base-content/55"
              >
                Generating...
              </span>
            </p>
            <p
              :if={!pending_exchange?(exchange) && exchange.sources != []}
              class="mt-3 text-xs text-base-content/55"
            >
              Sources used: {Enum.join(exchange.sources, ", ")}
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
          disabled={@loading || !@client_online}
          class="input input-bordered min-w-0 flex-1"
        />
        <button type="submit" class="btn btn-primary shrink-0" disabled={@loading || !@client_online}>
          <span :if={!@loading}>Send</span>
          <span :if={@loading}>Asking...</span>
        </button>
      </.form>
    </main>
    """
  end

  defp start_streaming_answer(socket, question) do
    parent = self()
    stream_ref = make_ref()
    Conversations.get_or_create_session(socket.assigns.chat_session_id)

    task =
      Task.Supervisor.async_nolink(BeaconAssistant.ChatTaskSupervisor, fn ->
        ask_and_notify(parent, stream_ref, question, socket.assigns.chat_session_id)
      end)

    socket
    |> assign(
      loading: true,
      active_stream_ref: stream_ref,
      active_task_ref: task.ref,
      error: nil,
      form: to_form(%{"question" => ""}, as: :chat)
    )
    |> update(:exchanges, &(&1 ++ [pending_exchange(stream_ref, question)]))
  end

  defp ask_and_notify(parent, stream_ref, question, chat_session_id) do
    result =
      try do
        Chatbot.ask_stream(question,
          chat_session_id: chat_session_id,
          on_delta: fn delta -> send(parent, {:chat_stream_delta, stream_ref, delta}) end
        )
      rescue
        exception ->
          Logger.error("chat_live.ask_stream raised error=#{Exception.message(exception)}")
          {:error, :critical}
      catch
        kind, reason ->
          Logger.error(
            "chat_live.ask_stream threw kind=#{inspect(kind)} reason=#{inspect(reason)}"
          )

          {:error, :critical}
      end

    case result do
      {:ok, exchange} ->
        message =
          if exchange_status(exchange) == "failed" do
            :chat_stream_failed
          else
            :chat_stream_done
          end

        send(parent, {message, stream_ref, exchange})

      {:error, _reason} ->
        send(
          parent,
          {:chat_stream_failed, stream_ref, failed_pending_exchange(stream_ref, question)}
        )
    end

    :ok
  end

  defp pending_exchange(stream_ref, question) do
    %{
      id: stream_ref,
      question: question,
      answer: "",
      status: "streaming",
      sources: [],
      pending?: true
    }
  end

  defp failed_pending_exchange(stream_ref, question) do
    %{
      id: stream_ref,
      question: question,
      answer: ErrorHandling.critical_message(),
      status: "failed",
      sources: [],
      pending?: false
    }
  end

  defp append_pending_answer_delta(exchanges, stream_ref, delta) do
    Enum.map(exchanges, fn
      %{id: ^stream_ref, pending?: true} = exchange ->
        %{exchange | answer: exchange.answer <> delta}

      exchange ->
        exchange
    end)
  end

  defp replace_pending_exchange(exchanges, stream_ref, exchange) do
    Enum.map(exchanges, fn
      %{id: ^stream_ref, pending?: true} -> exchange
      current_exchange -> current_exchange
    end)
  end

  defp pending_question(exchanges, stream_ref) do
    Enum.find_value(exchanges, "", fn
      %{id: ^stream_ref, question: question} -> question
      _exchange -> nil
    end)
  end

  defp pending_exchange?(exchange), do: Map.get(exchange, :pending?, false)
  defp exchange_answer(exchange), do: Map.get(exchange, :answer) || ""
  defp exchange_status(exchange), do: exchange |> Map.get(:status) |> to_string()

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
