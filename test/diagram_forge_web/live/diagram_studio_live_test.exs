defmodule DiagramForgeWeb.DiagramStudioLiveTest do
  use DiagramForgeWeb.ConnCase
  use Oban.Testing, repo: DiagramForge.Repo

  import Phoenix.LiveViewTest
  import Mox

  alias DiagramForge.Diagrams
  alias DiagramForge.MockAIClient

  setup :verify_on_exit!

  describe "mount" do
    test "initializes with empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert view
             |> element("#upload-form")
             |> has_element?()

      assert has_element?(view, "h1", "DiagramForge Studio")
    end

    test "loads existing documents", %{conn: conn} do
      document = fixture(:document)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ document.title
    end
  end

  describe "update_prompt" do
    test "updates prompt assign", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Update prompt
      view
      |> element("textarea[name='prompt']")
      |> render_change(%{"prompt" => "Create a GenServer diagram"})

      # The prompt should be in the textarea value
      assert view
             |> element("textarea[name='prompt']")
             |> render() =~ "Create a GenServer diagram"
    end
  end

  describe "generate_from_prompt" do
    test "generates diagram from prompt and displays it for authenticated user", %{conn: conn} do
      user = fixture(:user)

      ai_response = %{
        "title" => "GenServer Flow",
        "domain" => "elixir",
        "level" => "intermediate",
        "tags" => ["otp"],
        "mermaid" => "flowchart TD\n  A[Start] --> B[GenServer]",
        "summary" => "Shows GenServer flow",
        "notes_md" => "# Notes\n\nTest notes"
      }

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Update prompt
      view
      |> element("textarea[name='prompt']")
      |> render_change(%{"prompt" => "Create a GenServer diagram"})

      # Generate diagram - MockAIClient will be used automatically
      view
      |> element("form[phx-submit='generate_from_prompt']")
      |> render_submit()

      # Wait for async generation to complete by rendering again
      # This processes the {:do_generate_from_prompt, prompt} message
      html = render(view)

      # Verify diagram was generated and is displayed
      assert html =~ "GenServer Flow"
      assert html =~ "Shows GenServer flow"
      assert html =~ "Save Diagram"
      assert html =~ "Discard"

      # Diagram should NOT be in database yet (needs to be saved)
      diagrams = Diagrams.list_diagrams()
      assert diagrams == []

      # Click Save button
      view
      |> element("button", "Save Diagram")
      |> render_click()

      # Now diagram should be in database
      diagrams = Diagrams.list_diagrams()
      assert length(diagrams) == 1
      diagram = hd(diagrams)
      assert diagram.title == "GenServer Flow"
      assert diagram.user_id == user.id
    end

    test "redirects to OAuth when unauthenticated user tries to save generated diagram",
         %{conn: conn} do
      ai_response = %{
        "title" => "GenServer Flow",
        "domain" => "elixir",
        "level" => "intermediate",
        "tags" => ["otp"],
        "mermaid" => "flowchart TD\n  A[Start] --> B[GenServer]",
        "summary" => "Shows GenServer flow",
        "notes_md" => "# Notes\n\nTest notes"
      }

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      {:ok, view, _html} = live(conn, ~p"/")

      # Update prompt
      view
      |> element("textarea[name='prompt']")
      |> render_change(%{"prompt" => "Create a GenServer diagram"})

      # Generate diagram
      view
      |> element("form[phx-submit='generate_from_prompt']")
      |> render_submit()

      # Wait for async generation to complete
      render(view)

      # Click Save button without being authenticated
      result =
        view
        |> element("button", "Save Diagram")
        |> render_click()

      # Should redirect to OAuth with pending diagram data
      assert {:error, {:redirect, %{to: redirect_path}}} = result
      assert redirect_path =~ "/auth/github?pending_diagram="

      # Diagram should NOT be saved to database when user is not authenticated
      diagrams = Diagrams.list_diagrams()
      assert diagrams == [], "Diagram should not be saved when user is unauthenticated"
    end

    test "does not create diagram when prompt is empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Try to submit with empty prompt
      view
      |> element("form[phx-submit='generate_from_prompt']")
      |> render_submit()

      # Verify no diagram was created
      diagrams = Diagrams.list_diagrams()
      assert diagrams == []
    end

    test "submit button is disabled when prompt is empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Verify submit button is disabled initially
      assert view
             |> element("button[type='submit'][disabled]", "Generate Diagram")
             |> has_element?()
    end
  end

  describe "handle_info - document_updated" do
    test "refreshes document list when document is updated", %{conn: conn} do
      document = fixture(:document, title: "Original Title")

      {:ok, view, _html} = live(conn, ~p"/")

      # Verify original title
      assert render(view) =~ "Original Title"

      # Simulate document update via PubSub
      {:ok, updated_doc} = Diagrams.update_document(document, %{title: "Updated Title"})

      Phoenix.PubSub.broadcast(
        DiagramForge.PubSub,
        "documents",
        {:document_updated, updated_doc.id}
      )

      # Give LiveView time to process the message
      :timer.sleep(50)

      # Verify updated title
      assert render(view) =~ "Updated Title"
      refute render(view) =~ "Original Title"
    end
  end

  describe "file upload" do
    test "displays upload area and accepts files", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Verify upload area exists
      assert has_element?(view, "#upload-form")
      assert render(view) =~ "Click or drag PDF/MD"

      # Verify upload button is disabled when no file is selected
      assert view
             |> element("button[type='submit'][disabled]")
             |> has_element?()
    end
  end

  # The following tests would be added based on the actual LiveView implementation
  # These are placeholder tests showing what should be tested once the UI is implemented

  # describe "tag filtering" do
  #   test "adds tag to active filter", %{conn: conn} do
  #     user = fixture(:user)
  #     fixture(:diagram, user: user, tags: ["elixir"])
  #     fixture(:diagram, user: user, tags: ["rust"])
  #
  #     conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
  #     {:ok, view, _html} = live(conn, ~p"/")
  #
  #     # Click tag to add to filter
  #     view
  #     |> element("button[phx-click='add_tag_to_filter'][phx-value-tag='elixir']")
  #     |> render_click()
  #
  #     html = render(view)
  #
  #     # Verify tag appears in active filter chips
  #     assert html =~ "elixir"
  #     # Verify only elixir diagrams shown
  #   end
  #
  #   test "removes tag from filter", %{conn: conn} do
  #     # Test implementation
  #   end
  #
  #   test "clears all filters", %{conn: conn} do
  #     # Test implementation
  #   end
  # end

  # describe "saved filter management" do
  #   test "saves current filter", %{conn: conn} do
  #     # Test implementation
  #   end
  #
  #   test "applies saved filter", %{conn: conn} do
  #     # Test implementation
  #   end
  #
  #   test "deletes saved filter", %{conn: conn} do
  #     # Test implementation
  #   end
  #
  #   test "pins/unpins filter", %{conn: conn} do
  #     # Test implementation
  #   end
  #
  #   test "reorders filters", %{conn: conn} do
  #     # Test implementation
  #   end
  # end

  # describe "tag management on diagrams" do
  #   test "adds tags to diagram", %{conn: conn} do
  #     # Test implementation
  #   end
  #
  #   test "removes tag from diagram", %{conn: conn} do
  #     # Test implementation
  #   end
  # end

  # describe "fork diagram with tags" do
  #   test "forks diagram and copies tags", %{conn: conn} do
  #     user = fixture(:user)
  #     original = fixture(:diagram, user: user, tags: ["elixir", "original"])
  #
  #     conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
  #     {:ok, view, _html} = live(conn, ~p"/")
  #
  #     view
  #     |> element("button[phx-click='fork_diagram'][phx-value-id='#{original.id}']")
  #     |> render_click()
  #
  #     # Verify fork was created with tags
  #     diagrams = Diagrams.list_diagrams()
  #     assert length(diagrams) == 2
  #
  #     forked = Enum.find(diagrams, fn d -> d.id != original.id end)
  #     assert forked.tags == original.tags
  #   end
  # end
end
