defmodule BeaconAssistantWeb.ChatLive do
  use BeaconAssistantWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Beacon Support Assistant",
        exchanges: [],
        loading: false,
        error: nil
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-3xl px-6 py-12">
      <p class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
        Scaffold
      </p>

      <h1 class="mt-2 text-4xl font-semibold tracking-normal">
        Beacon Support Assistant
      </h1>

      <p class="mt-4 text-base leading-7 text-base-content/70">
        Phoenix LiveView, Ecto, and PostgreSQL are ready. Chat, knowledge-base grounding,
        persistence, and LLM integration are intentionally left for the next feature steps.
      </p>

      <section class="mt-8 rounded-lg border border-base-300 bg-base-100 p-6">
        <h2 class="text-lg font-semibold">Application boundaries</h2>
        <ul class="mt-4 space-y-2 text-sm text-base-content/75">
          <li><code>BeaconAssistant.Chatbot</code></li>
          <li><code>BeaconAssistant.KnowledgeBase</code></li>
          <li><code>BeaconAssistant.LLMClient</code></li>
          <li><code>BeaconAssistant.Conversations</code></li>
        </ul>
      </section>
    </main>
    """
  end
end
