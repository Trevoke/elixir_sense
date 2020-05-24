defmodule ElixirSense.Providers.Suggestion.Reducers.Callbacks do
  @moduledoc false

  alias ElixirSense.Core.Introspection
  alias ElixirSense.Core.State

  @type callback :: %{
          type: :callback,
          name: String.t(),
          arity: non_neg_integer,
          args: String.t(),
          origin: String.t(),
          summary: String.t(),
          spec: String.t(),
          metadata: map
        }

  @doc """
  A reducer that adds suggestions of callbacks.
  """
  def add_callbacks(hint, text_before, env, _buffer_metadata, acc) do
    %State.Env{protocol: protocol, behaviours: behaviours, scope: scope} = env

    list =
      Enum.flat_map(behaviours, fn
        mod when is_atom(mod) and (protocol == nil or mod != elem(protocol, 0)) ->
          mod_name = inspect(mod)

          for %{
                name: name,
                arity: arity,
                callback: spec,
                signature: signature,
                doc: doc,
                metadata: metadata
              } <-
                Introspection.get_callbacks_with_docs(mod),
              def_prefix?(hint, spec) or String.starts_with?("#{name}", hint) do
            desc = Introspection.extract_summary_from_docs(doc)
            [_, args_str] = Regex.run(Regex.recompile!(~r/.\((.*)\)/), signature)
            args = args_str |> String.replace(Regex.recompile!(~r/\s/), "")

            %{
              type: :callback,
              name: Atom.to_string(name),
              arity: arity,
              args: args,
              origin: mod_name,
              summary: desc,
              spec: spec,
              metadata: metadata
            }
          end

        _ ->
          []
      end)

    list = Enum.sort(list)

    cond do
      Regex.match?(~r/\s(def|defmacro)\s+[a-z|_]*$/, text_before) ->
        {:halt, %{acc | result: list}}

      match?({_f, _a}, scope) ->
        {:cont, acc}

      true ->
        {:cont, %{acc | result: acc.result ++ list}}
    end
  end

  defp def_prefix?(hint, spec) do
    if String.starts_with?(spec, "@macrocallback") do
      String.starts_with?("defmacro", hint)
    else
      String.starts_with?("def", hint)
    end
  end
end
