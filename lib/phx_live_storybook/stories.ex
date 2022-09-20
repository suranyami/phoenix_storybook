defmodule PhxLiveStorybook.ComponentStory do
  @moduledoc false
  defstruct [
    :module,
    :storybook_path,
    :name,
    :icon,
    :description
  ]
end

defmodule PhxLiveStorybook.PageStory do
  @moduledoc false
  defstruct [
    :module,
    :storybook_path,
    :name,
    :icon,
    :description,
    :navigation
  ]
end

defmodule PhxLiveStorybook.Folder do
  @moduledoc false
  defstruct [:name, :nice_name, :items, :storybook_path, :icon]
end

# This module performs a recursive scan of all files/folders under :content_path
# and creates an in-memory tree hierarchy of content using above Story structs.
defmodule PhxLiveStorybook.Stories do
  @moduledoc false
  alias PhxLiveStorybook.{ComponentStory, Folder, PageStory}

  @doc false
  def stories(path, folders_config) do
    if path && File.dir?(path) do
      recursive_scan(path, folders_config)
    else
      []
    end
  end

  defp recursive_scan(path, folders_config, storybook_path \\ "") do
    for file_name <- path |> File.ls!() |> Enum.sort(:desc),
        file_path = Path.join(path, file_name),
        reduce: [] do
      acc ->
        cond do
          File.dir?(file_path) ->
            storybook_path = Path.join(["/", storybook_path, file_name])
            folder_config = Keyword.get(folders_config, String.to_atom(storybook_path), [])

            [
              folder_story(
                file_name,
                folder_config,
                storybook_path,
                recursive_scan(file_path, folders_config, storybook_path)
              )
              | acc
            ]

          Path.extname(file_path) == ".exs" ->
            story_module = story_module(file_path)

            unless Code.ensure_loaded?(story_module) do
              Code.eval_file(file_path)
            end

            case story_type(story_module) do
              nil ->
                acc

              type when type in [:component, :live_component] ->
                [component_story(story_module, storybook_path) | acc]

              :page ->
                [page_story(story_module, storybook_path) | acc]
            end

          true ->
            acc
        end
    end
    |> sort_stories()
  end

  defp folder_story(file_name, folder_config, storybook_path, items) do
    %Folder{
      name: file_name,
      nice_name:
        Keyword.get_lazy(folder_config, :name, fn ->
          file_name |> String.capitalize() |> String.replace("_", " ")
        end),
      storybook_path: storybook_path,
      items: items,
      icon: folder_config[:icon]
    }
  end

  defp component_story(module, storybook_path) do
    module_name = module |> to_string() |> String.split(".") |> Enum.at(-1)

    %ComponentStory{
      module: module,
      storybook_path: Path.join(["/", storybook_path, Macro.underscore(module_name)]),
      name: module.name(),
      description: module.description(),
      icon: module.icon()
    }
  end

  defp page_story(module, storybook_path) do
    module_name = module |> to_string() |> String.split(".") |> Enum.at(-1)

    %PageStory{
      module: module,
      storybook_path: Path.join(["/", storybook_path, Macro.underscore(module_name)]),
      name: module.name(),
      description: module.description(),
      icon: module.icon(),
      navigation: module.navigation()
    }
  end

  @story_priority %{PageStory => 0, ComponentStory => 1, Folder => 2}
  defp sort_stories(stories) do
    Enum.sort_by(stories, &Map.get(@story_priority, &1.__struct__))
  end

  defp story_module(story_path) do
    {:ok, contents} = File.read(story_path)

    case Regex.run(~r/defmodule\s+([^\s]+)\s+do/, contents, capture: :all_but_first) do
      nil -> nil
      [module_name] -> String.to_atom("Elixir.#{module_name}")
    end
  end

  defp story_type(story_module) do
    fun = :storybook_type

    if Kernel.function_exported?(story_module, fun, 0) do
      apply(story_module, fun, [])
    else
      nil
    end
  end

  def all_leaves(stories, acc \\ []) do
    Enum.flat_map(stories, fn story ->
      case story do
        %ComponentStory{} -> [story | acc]
        %PageStory{} -> [story | acc]
        %Folder{items: items} -> all_leaves(items, acc)
      end
    end)
  end

  def flat_list(stories, acc \\ []) do
    Enum.flat_map(stories, fn story ->
      case story do
        %ComponentStory{} -> [story | acc]
        %PageStory{} -> [story | acc]
        %Folder{items: items} -> [story | flat_list(items, acc)]
      end
    end)
  end
end
