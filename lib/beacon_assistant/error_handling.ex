defmodule BeaconAssistant.ErrorHandling do
  @moduledoc """
  Normalizes internal failures into stable categories and user-facing messages.
  """

  require Logger

  @model_timeout_message "The model is taking too long to respond. Please try again."
  @critical_message "Something went wrong. Please try again later."
  @offline_message "You appear to be offline. Connect to the internet before sending a request."
  @knowledge_base_message "I'm not able to retrieve that information from the available knowledge base."

  def model_timeout_message, do: @model_timeout_message
  def critical_message, do: @critical_message
  def offline_message, do: @offline_message
  def knowledge_base_message, do: @knowledge_base_message

  def user_message(:model_timeout), do: @model_timeout_message
  def user_message(:critical), do: @critical_message
  def user_message(:knowledge_base), do: @knowledge_base_message
  def user_message(_category), do: @critical_message

  def classify(:timeout), do: :model_timeout
  def classify(:receive_timeout), do: :model_timeout
  def classify({:timeout, _details}), do: :model_timeout
  def classify({:transport_error, :timeout}), do: :model_timeout
  def classify({:transport_error, :receive_timeout}), do: :model_timeout
  def classify(%Req.TransportError{reason: reason}), do: classify({:transport_error, reason})
  def classify(:model_timeout), do: :model_timeout

  def classify(:no_knowledge_base_documents), do: :knowledge_base
  def classify(:knowledge_base_unavailable), do: :knowledge_base
  def classify(:empty_question), do: :validation

  def classify(_reason), do: :critical

  def normalize_llm_result({:error, reason, metadata}) do
    {:error, classify_llm(reason), Map.put(metadata || %{}, :error_reason, inspect(reason))}
  end

  def normalize_llm_result({:error, reason}) do
    {:error, classify_llm(reason)}
  end

  def normalize_llm_result(result), do: result

  def classify_llm(reason) do
    case classify(reason) do
      :model_timeout -> :model_timeout
      _category -> :critical
    end
  end

  def safe_call(label, fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception ->
      Logger.error("#{label} raised error=#{Exception.message(exception)}")
      {:error, {:exception, exception.__struct__}}
  catch
    kind, reason ->
      Logger.error("#{label} threw kind=#{inspect(kind)} reason=#{inspect(reason)}")
      {:error, {kind, reason}}
  end
end
