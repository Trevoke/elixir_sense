defmodule Alchemist.API.Eval do

  @moduledoc false

  alias ElixirSense.Core.Metadata
  alias ElixirSense.Core.Parser
  alias ElixirSense.Core.Ast
  alias ElixirSense.Core.State
  alias ElixirSense.Core.Introspection

  def request(args) do
    _no_return =
      args
      |> normalize
      |> process

    IO.puts "END-OF-EVAL"
  end

  def process({:signature_info, buffer_file, file, line}) do
    buffer = File.read!(buffer_file)
    prefix = File.read!(file)

    case ElixirSense.signature(prefix, buffer, line) do
      %{active_parameter: npar, signatures: signatures} ->
        IO.puts "#{npar}"
        IO.puts format_signatures(signatures)
      :none ->
        IO.puts "none"
    end
  end

  def process({:match, file}) do
    try do
      file_content = File.read!("#{file}")
      {:=, _, [pattern|_]} = file_content |> Code.string_to_quoted!
      vars = extract_vars(pattern)

      bindings = file_content
      |> Code.eval_string
      |> Tuple.to_list
      |> List.last

      if Enum.empty?(vars) do
        IO.puts "# No bindings"
      else
        IO.puts "# Bindings"
      end

      Enum.each(vars, fn var ->
        IO.puts ""
        IO.write "#{var} = "
        IO.inspect Keyword.get(bindings, var)
      end)
    rescue
      e -> print_match_error(e)
    end
  end

  def process({:quote, file}) do
    File.read!("#{file}")
    |> Code.string_to_quoted
    |> Tuple.to_list
    |> List.last
    |> IO.inspect
  end

  def process({:expand_full, buffer_file, file, line}) do
    try do
      {_, expr} = File.read!("#{file}") |> Code.string_to_quoted
      env = create_env(buffer_file, line)
      expand_and_print(&Macro.expand_once/2, expr, env)
      IO.puts("\u000B")
      expand_and_print(&Macro.expand/2, expr, env)
      IO.puts("\u000B")
      expand_and_print(&Ast.expand_partial/2, expr, env)
      IO.puts("\u000B")
      expand_and_print(&Ast.expand_all/2, expr, env)
    rescue
      e -> IO.inspect e
    end
  end

  defp expand_and_print(expand_func, expr, env) do
    expand_func.(expr, env)
    |> Macro.to_string
    |> IO.puts
  end

  def normalize(request) do
    {expr , _} = Code.eval_string(request)
    expr
  end

  defp extract_vars(ast) do
    {_ast, acc} = Macro.postwalk(ast, [], &extract_var/2)
    acc |> Enum.reverse
  end

  defp extract_var(ast = {var_name, [line: _], nil}, acc) when is_atom(var_name) and var_name != :_ do
    {ast, [var_name|acc]}
  end

  defp extract_var(ast, acc) do
    {ast, acc}
  end

  defp print_match_error(%{__struct__: type, description: description, line: line}) do
    IO.puts "# #{Introspection.module_to_string(type)} on line #{line}:\n#  ↳ #{description}"
  end

  defp print_match_error(%MatchError{}) do
    IO.puts "# No match"
  end

  defp create_env(file, line) do
    %State.Env{requires: requires, imports: imports, module: module} =
      file
      |> Parser.parse_file(true, true, line)
      |> Metadata.get_env(line)

    __ENV__
    |> Ast.add_requires_to_env(requires)
    |> Ast.add_imports_to_env(imports)
    |> Ast.set_module_for_env(module)
  end

  defp format_signatures(signatures) do
    for %{name: name, params: params} <- signatures do
      fun_args_text = params |> Enum.join(",") |> String.replace("\\\\", "\\\\\\\\")
      "#{name};#{fun_args_text}"
    end |> Enum.join("\n")
  end

end
