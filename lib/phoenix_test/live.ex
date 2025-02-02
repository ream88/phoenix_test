defmodule PhoenixTest.Live do
  @moduledoc false
  @endpoint Application.compile_env(:phoenix_test, :endpoint)

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  defstruct view: nil, conn: nil, private: %{}

  def build(conn) do
    {:ok, view, _html} = live(conn)
    %__MODULE__{view: view, conn: conn}
  end

  def get_private(%__MODULE__{private: private}, key) do
    Map.get(private, key, :not_found)
  end

  def pop_private(%__MODULE__{private: private} = session, key) do
    {popped, rest_private} = Map.pop(private, key, %{})
    {popped, %{session | private: rest_private}}
  end

  def put_private(%{private: private} = session, key, value) do
    new_private = Map.put(private, key, value)

    %{session | private: new_private}
  end
end

defimpl PhoenixTest.Driver, for: PhoenixTest.Live do
  @endpoint Application.compile_env(:phoenix_test, :endpoint)

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixTest.Html
  alias PhoenixTest.Query

  def click_link(session, text) do
    click_link(session, "a", text)
  end

  def click_link(session, selector, text) do
    result =
      session.view
      |> element(selector, text)
      |> render_click()
      |> maybe_redirect(session)

    case result do
      {:ok, view, _} ->
        %{session | view: view}

      {:static_view, conn, path} ->
        PhoenixTest.visit(conn, path)
    end
  end

  def click_button(session, text) do
    click_button(session, "button", text)
  end

  def click_button(session, selector, text) do
    if has_active_form?(session) do
      session
      |> render_html()
      |> Query.find_submit_buttons(selector, text)

      session
      |> submit_active_form()
    else
      regular_click(session, selector, text)
    end
  end

  defp has_active_form?(session) do
    case PhoenixTest.Live.get_private(session, :active_form) do
      :not_found -> false
      _ -> true
    end
  end

  defp submit_active_form(session) do
    {form, session} = PhoenixTest.Live.pop_private(session, :active_form)

    session.view
    |> form(form.selector, form.form_data)
    |> render_submit()

    session
  end

  defp regular_click(session, selector, text) do
    result =
      session.view
      |> element(selector, text)
      |> render_click()
      |> maybe_redirect(session)

    case result do
      {:ok, view, _} ->
        %{session | view: view}

      {:static_view, conn, path} ->
        PhoenixTest.visit(conn, path)
    end
  end

  def fill_form(session, selector, form_data) do
    if phx_change_form?(session, selector) do
      session.view
      |> form(selector, form_data)
      |> render_change()
    else
      validate_fields(session, selector, form_data)
    end

    session
    |> PhoenixTest.Live.put_private(:active_form, %{selector: selector, form_data: form_data})
  end

  defp validate_fields(session, selector, form_data) do
    html = render_html(session)

    Enum.each(form_data, fn {name, _value} ->
      Query.find!(html, "#{selector} [name=#{name}]")
    end)
  end

  defp phx_change_form?(session, selector) do
    phx_change =
      session
      |> render_html()
      |> Query.find!(selector)
      |> Html.attribute("phx-change")

    phx_change != nil && phx_change != ""
  end

  def submit_form(session, selector, form_data) do
    session.view
    |> form(selector, form_data)
    |> render_submit()

    session
  end

  def render_html(%{view: view}) do
    render(view)
  end

  defp maybe_redirect({:error, {:redirect, %{to: path}}}, session) do
    {:static_view, session.conn, path}
  end

  defp maybe_redirect({:error, {:live_redirect, _}} = result, session) do
    result
    |> follow_redirect(session.conn)
  end

  defp maybe_redirect(html, session) when is_binary(html) do
    {:ok, session.view, html}
  end
end
