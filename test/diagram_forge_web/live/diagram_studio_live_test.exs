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

      # Unauthenticated users see login prompt instead of upload form
      assert render(view) =~ "Sign in to upload documents"
      assert has_element?(view, "h1", "DiagramForge Studio")
    end

    test "shows upload form for authenticated users", %{conn: conn} do
      user = fixture(:user)
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
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

      # Verify that user_id and operation are properly passed to AI client
      expect(MockAIClient, :chat!, fn _messages, opts ->
        assert opts[:user_id] == user.id, "user_id must be passed to AI client for usage tracking"
        assert opts[:operation] == "diagram_generation", "operation must be passed to AI client"
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
      # Check for unsaved diagram buttons
      assert html =~ "save_generated_diagram"
      assert html =~ "Discard"

      # Diagram should NOT be in database yet (needs to be saved)
      diagrams = Diagrams.list_diagrams()
      assert diagrams == []

      # Click Save button
      view
      |> element("button[phx-click='save_generated_diagram']")
      |> render_click()

      # Now diagram should be in database
      diagrams = Diagrams.list_owned_diagrams(user.id)
      assert length(diagrams) == 1
      diagram = hd(diagrams)
      assert diagram.title == "GenServer Flow"

      # Verify user owns the diagram
      assert Diagrams.user_owns_diagram?(diagram.id, user.id)
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

      # Unauthenticated users have track_usage: false since we can't attribute usage
      expect(MockAIClient, :chat!, fn _messages, opts ->
        assert opts[:user_id] == nil, "unauthenticated user should have nil user_id"

        assert opts[:track_usage] == false,
               "usage tracking should be disabled for unauthenticated users"

        assert opts[:operation] == "diagram_generation", "operation must still be passed"
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
        |> element("button[phx-click='save_generated_diagram']")
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
    test "displays upload area and accepts files for authenticated users", %{conn: conn} do
      user = fixture(:user)
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Verify upload area exists with instructional text
      assert has_element?(view, "#upload-form")
      assert render(view) =~ "Upload a document"
      assert render(view) =~ "PDF, Markdown, or Text"

      # Verify upload button is not shown when no file is selected
      # (button only appears after selecting a file)
      refute has_element?(view, "#upload-form button[type='submit']")
    end

    test "shows login prompt for unauthenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Unauthenticated users see login prompt instead of upload form
      refute html =~ "id=\"upload-form\""
      assert html =~ "Sign in to upload documents"
      assert html =~ "Upload a document"
      assert html =~ "PDF, Markdown, or Text"
    end

    test "rejects files with invalid type", %{conn: conn} do
      user = fixture(:user)
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Try to upload a .exe file (not accepted)
      invalid_file =
        file_input(view, "#upload-form", :document, [
          %{
            name: "malware.exe",
            content: "fake executable content",
            type: "application/octet-stream"
          }
        ])

      render_upload(invalid_file, "malware.exe")

      # Should display error message
      assert render(view) =~ "Invalid file type"
    end

    test "rejects files that are too large", %{conn: conn} do
      user = fixture(:user)
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Create content larger than 2MB (2_000_000 bytes)
      large_content = String.duplicate("x", 2_500_000)

      large_file =
        file_input(view, "#upload-form", :document, [
          %{
            name: "large_document.txt",
            content: large_content,
            type: "text/plain"
          }
        ])

      render_upload(large_file, "large_document.txt")

      # Should display error message
      assert render(view) =~ "File is too large"
    end

    test "accepts valid PDF files", %{conn: conn} do
      user = fixture(:user)
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      valid_file =
        file_input(view, "#upload-form", :document, [
          %{
            name: "document.pdf",
            content: "PDF content",
            type: "application/pdf"
          }
        ])

      render_upload(valid_file, "document.pdf")

      # Should show the file name without errors
      html = render(view)
      assert html =~ "document.pdf"
      refute html =~ "Invalid file type"
      refute html =~ "File is too large"
    end

    test "accepts valid text files", %{conn: conn} do
      user = fixture(:user)
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      valid_file =
        file_input(view, "#upload-form", :document, [
          %{
            name: "notes.txt",
            content: "Some text content for diagram generation",
            type: "text/plain"
          }
        ])

      render_upload(valid_file, "notes.txt")

      # Should show the file name without errors
      html = render(view)
      assert html =~ "notes.txt"
      refute html =~ "Invalid file type"
      refute html =~ "File is too large"
    end

    test "accepts valid markdown files", %{conn: conn} do
      user = fixture(:user)
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      valid_file =
        file_input(view, "#upload-form", :document, [
          %{
            name: "readme.md",
            content: "# Heading\n\nSome markdown content",
            type: "text/markdown"
          }
        ])

      render_upload(valid_file, "readme.md")

      # Should show the file name without errors
      html = render(view)
      assert html =~ "readme.md"
      refute html =~ "Invalid file type"
      refute html =~ "File is too large"
    end
  end

  describe "tag filtering" do
    test "adds tag to active filter", %{conn: conn} do
      user = fixture(:user)
      elixir_diagram = fixture(:diagram, tags: ["elixir"])
      rust_diagram = fixture(:diagram, tags: ["rust"])
      Diagrams.assign_diagram_to_user(elixir_diagram.id, user.id, true)
      Diagrams.assign_diagram_to_user(rust_diagram.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, html} = live(conn, ~p"/")

      # Both diagrams should be visible initially
      assert html =~ elixir_diagram.title
      assert html =~ rust_diagram.title

      # Add "elixir" tag to filter by clicking in tag cloud
      view
      |> element("button[phx-click='add_tag_to_filter'][phx-value-tag='elixir']")
      |> render_click()

      html = render(view)

      # Verify tag appears in active filter chips
      assert html =~ "elixir"
      # Only elixir diagram should be shown
      assert html =~ elixir_diagram.title
      refute html =~ rust_diagram.title
    end

    test "removes tag from filter", %{conn: conn} do
      user = fixture(:user)
      elixir_diagram = fixture(:diagram, tags: ["elixir"])
      rust_diagram = fixture(:diagram, tags: ["rust"])
      Diagrams.assign_diagram_to_user(elixir_diagram.id, user.id, true)
      Diagrams.assign_diagram_to_user(rust_diagram.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Add tag to filter first by clicking in tag cloud
      view
      |> element("button[phx-click='add_tag_to_filter'][phx-value-tag='elixir']")
      |> render_click()

      # Remove the tag from filter
      view
      |> element("button[phx-click='remove_tag_from_filter'][phx-value-tag='elixir']")
      |> render_click()

      html = render(view)

      # Both diagrams should be visible again
      assert html =~ elixir_diagram.title
      assert html =~ rust_diagram.title
    end

    test "clears all filters", %{conn: conn} do
      user = fixture(:user)
      diagram1 = fixture(:diagram, tags: ["elixir"])
      diagram2 = fixture(:diagram, tags: ["rust"])
      Diagrams.assign_diagram_to_user(diagram1.id, user.id, true)
      Diagrams.assign_diagram_to_user(diagram2.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Add tag to filter by clicking in tag cloud
      view
      |> element("button[phx-click='add_tag_to_filter'][phx-value-tag='elixir']")
      |> render_click()

      # Clear all filters
      view
      |> element("button[phx-click='clear_filter']")
      |> render_click()

      html = render(view)

      # Both diagrams should be visible
      assert html =~ diagram1.title
      assert html =~ diagram2.title
    end

    test "filters diagrams by multiple tags (OR logic)", %{conn: conn} do
      user = fixture(:user)
      both_tags = fixture(:diagram, tags: ["elixir", "phoenix"])
      elixir_only = fixture(:diagram, tags: ["elixir"])
      rust_only = fixture(:diagram, tags: ["rust"])
      Diagrams.assign_diagram_to_user(both_tags.id, user.id, true)
      Diagrams.assign_diagram_to_user(elixir_only.id, user.id, true)
      Diagrams.assign_diagram_to_user(rust_only.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Add first tag by clicking in tag cloud
      view
      |> element("button[phx-click='add_tag_to_filter'][phx-value-tag='elixir']")
      |> render_click()

      # Add second tag by clicking in tag cloud
      view
      |> element("button[phx-click='add_tag_to_filter'][phx-value-tag='phoenix']")
      |> render_click()

      html = render(view)

      # OR logic: diagrams with elixir OR phoenix should be visible
      assert html =~ both_tags.title
      assert html =~ elixir_only.title
      # Diagram with neither tag should not be visible
      refute html =~ rust_only.title
    end
  end

  describe "saved filter management" do
    test "saves current filter", %{conn: conn} do
      user = fixture(:user)
      diagram = fixture(:diagram, tags: ["elixir"])
      Diagrams.assign_diagram_to_user(diagram.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Add tag to create an active filter by clicking in tag cloud
      view
      |> element("button[phx-click='add_tag_to_filter'][phx-value-tag='elixir']")
      |> render_click()

      # Show the save filter modal
      view
      |> element("button[phx-click='show_save_filter_modal']")
      |> render_click()

      # Save the filter
      view
      |> form("form[phx-submit='save_current_filter']", %{"name" => "My Elixir Filter"})
      |> render_submit()

      html = render(view)

      # Verify filter was saved (flash message)
      assert html =~ "Filter saved successfully"

      # Verify filter exists in database
      filters = Diagrams.list_saved_filters(user.id)
      assert length(filters) == 1
      assert hd(filters).name == "My Elixir Filter"
      assert hd(filters).tag_filter == ["elixir"]
    end

    test "applies saved filter", %{conn: conn} do
      user = fixture(:user)
      diagram1 = fixture(:diagram, tags: ["elixir"])
      diagram2 = fixture(:diagram, tags: ["rust"])
      Diagrams.assign_diagram_to_user(diagram1.id, user.id, true)
      Diagrams.assign_diagram_to_user(diagram2.id, user.id, true)

      # Create a saved filter
      {:ok, filter} =
        Diagrams.create_saved_filter(
          %{name: "Elixir Only", tag_filter: ["elixir"], is_pinned: true},
          user.id
        )

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Apply the saved filter
      view
      |> element("button[phx-click='apply_saved_filter'][phx-value-id='#{filter.id}']")
      |> render_click()

      html = render(view)

      # Only elixir diagram should be visible
      assert html =~ diagram1.title
      refute html =~ diagram2.title
    end

    test "deletes saved filter", %{conn: conn} do
      user = fixture(:user)

      # Create a saved filter
      {:ok, filter} =
        Diagrams.create_saved_filter(
          %{name: "To Delete", tag_filter: ["test"], is_pinned: true},
          user.id
        )

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, html} = live(conn, ~p"/")

      # Filter should be visible
      assert html =~ "To Delete"

      # Delete the filter
      view
      |> element("button[phx-click='delete_filter'][phx-value-id='#{filter.id}']")
      |> render_click()

      html = render(view)

      # Verify filter was deleted (flash message)
      assert html =~ "Filter deleted successfully"

      # Verify filter is gone from database
      filters = Diagrams.list_saved_filters(user.id)
      assert filters == []
    end
  end

  describe "tag management on diagrams" do
    test "adds tags to diagram via edit form", %{conn: conn} do
      user = fixture(:user)
      diagram = fixture(:diagram, tags: ["elixir"])
      Diagrams.assign_diagram_to_user(diagram.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Select the diagram first
      view
      |> element("div[phx-click='select_diagram'][phx-value-id='#{diagram.id}']")
      |> render_click()

      # Open edit modal
      view
      |> element("button[phx-click='edit_diagram'][phx-value-id='#{diagram.id}']")
      |> render_click()

      # Save with new tags
      view
      |> form("#edit-diagram-form", %{
        "diagram" => %{
          "title" => diagram.title,
          "diagram_source" => diagram.diagram_source,
          "tags" => "elixir, phoenix, otp"
        }
      })
      |> render_submit()

      html = render(view)

      # Verify success message
      assert html =~ "Diagram updated successfully"

      # Verify tags were added
      updated = Diagrams.get_diagram!(diagram.id)
      assert "elixir" in updated.tags
      assert "phoenix" in updated.tags
      assert "otp" in updated.tags
    end

    test "removes tag from diagram via edit form", %{conn: conn} do
      user = fixture(:user)
      diagram = fixture(:diagram, tags: ["elixir", "phoenix", "otp"])
      Diagrams.assign_diagram_to_user(diagram.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")

      # Select the diagram
      view
      |> element("div[phx-click='select_diagram'][phx-value-id='#{diagram.id}']")
      |> render_click()

      # Open edit modal
      view
      |> element("button[phx-click='edit_diagram'][phx-value-id='#{diagram.id}']")
      |> render_click()

      # Save with fewer tags
      view
      |> form("#edit-diagram-form", %{
        "diagram" => %{
          "title" => diagram.title,
          "diagram_source" => diagram.diagram_source,
          "tags" => "elixir"
        }
      })
      |> render_submit()

      # Verify tags were updated
      updated = Diagrams.get_diagram!(diagram.id)
      assert updated.tags == ["elixir"]
    end
  end

  describe "fork diagram with tags" do
    test "forks diagram and copies tags", %{conn: conn} do
      owner = fixture(:user)
      viewer = fixture(:user)
      # Create a public diagram owned by another user
      original = fixture(:diagram, tags: ["elixir", "original"], visibility: :public)
      Diagrams.assign_diagram_to_user(original.id, owner.id, true)

      # Log in as the viewer (not the owner)
      conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})

      # Navigate to the diagram via URL (public diagram)
      {:ok, view, _html} = live(conn, ~p"/d/#{original.id}")

      # Fork the diagram (Fork button shown for non-owners)
      view
      |> element("button[phx-click='fork_diagram'][phx-value-id='#{original.id}']")
      |> render_click()

      html = render(view)

      # Verify success message
      assert html =~ "Diagram forked successfully"

      # Verify fork was created with same tags
      owned_diagrams = Diagrams.list_owned_diagrams(viewer.id)
      assert length(owned_diagrams) == 1

      forked = List.first(owned_diagrams)
      assert forked.tags == original.tags
      assert forked.forked_from_id == original.id
    end

    test "fork preserves original diagram tags after modification", %{conn: conn} do
      owner = fixture(:user)
      viewer = fixture(:user)
      # Create a public diagram owned by another user
      original = fixture(:diagram, tags: ["elixir", "phoenix"], visibility: :public)
      Diagrams.assign_diagram_to_user(original.id, owner.id, true)

      # Log in as the viewer (not the owner)
      conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})

      # Navigate to the diagram via URL (public diagram)
      {:ok, view, _html} = live(conn, ~p"/d/#{original.id}")

      # Fork the diagram
      view
      |> element("button[phx-click='fork_diagram'][phx-value-id='#{original.id}']")
      |> render_click()

      # Get the forked diagram
      owned_diagrams = Diagrams.list_owned_diagrams(viewer.id)
      forked = List.first(owned_diagrams)

      # Modify the forked diagram's tags
      {:ok, _} = Diagrams.add_tags(forked, ["new-tag"], viewer.id)

      # Original should still have original tags
      original_refreshed = Diagrams.get_diagram!(original.id)
      assert original_refreshed.tags == ["elixir", "phoenix"]

      # Forked should have the new tag
      forked_refreshed = Diagrams.get_diagram!(forked.id)
      assert "new-tag" in forked_refreshed.tags
    end
  end

  describe "bookmark diagram" do
    test "bookmarks another user's public diagram", %{conn: conn} do
      owner = fixture(:user)
      viewer = fixture(:user)
      diagram = fixture(:diagram, tags: ["shared"], visibility: :public)
      Diagrams.assign_diagram_to_user(diagram.id, owner.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
      {:ok, view, _html} = live(conn, ~p"/d/#{diagram.id}")

      # Bookmark the diagram
      view
      |> element("button[phx-click='bookmark_diagram'][phx-value-id='#{diagram.id}']")
      |> render_click()

      html = render(view)

      # Verify success message
      assert html =~ "Diagram bookmarked successfully"

      # Verify bookmark exists
      bookmarked = Diagrams.list_bookmarked_diagrams(viewer.id)
      assert length(bookmarked) == 1
      assert hd(bookmarked).id == diagram.id
    end

    test "removes bookmark from diagram", %{conn: conn} do
      owner = fixture(:user)
      viewer = fixture(:user)
      diagram = fixture(:diagram, tags: ["shared"], visibility: :public)
      Diagrams.assign_diagram_to_user(diagram.id, owner.id, true)
      Diagrams.bookmark_diagram(diagram.id, viewer.id)

      conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
      {:ok, view, _html} = live(conn, ~p"/d/#{diagram.id}")

      # Remove the bookmark
      view
      |> element("button[phx-click='remove_bookmark'][phx-value-id='#{diagram.id}']")
      |> render_click()

      html = render(view)

      # Verify success message
      assert html =~ "removed from your collection"

      # Verify bookmark is gone
      bookmarked = Diagrams.list_bookmarked_diagrams(viewer.id)
      assert bookmarked == []
    end
  end

  describe "visibility controls" do
    test "owner can change diagram visibility", %{conn: conn} do
      user = fixture(:user)
      diagram = fixture(:diagram, visibility: :private)
      Diagrams.assign_diagram_to_user(diagram.id, user.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/d/#{diagram.id}")

      # Open edit modal
      view
      |> element("button[phx-click='edit_diagram'][phx-value-id='#{diagram.id}']")
      |> render_click()

      # Change visibility to public
      view
      |> form("#edit-diagram-form", %{
        "diagram" => %{
          "title" => diagram.title,
          "diagram_source" => diagram.diagram_source,
          "visibility" => "public"
        }
      })
      |> render_submit()

      # Verify visibility was changed
      updated = Diagrams.get_diagram!(diagram.id)
      assert updated.visibility == :public
    end

    test "non-owner cannot view private diagram", %{conn: conn} do
      owner = fixture(:user)
      viewer = fixture(:user)
      diagram = fixture(:diagram, visibility: :private)
      Diagrams.assign_diagram_to_user(diagram.id, owner.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})

      # Should redirect with error flash when trying to view private diagram
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/d/#{diagram.id}")

      assert flash["error"] =~ "permission"
    end

    test "anyone can view unlisted diagram with direct link", %{conn: conn} do
      owner = fixture(:user)
      viewer = fixture(:user)
      diagram = fixture(:diagram, visibility: :unlisted)
      Diagrams.assign_diagram_to_user(diagram.id, owner.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
      {:ok, _view, html} = live(conn, ~p"/d/#{diagram.id}")

      # Should be able to see the diagram
      assert html =~ diagram.title
      assert html =~ "Unlisted"
    end

    test "public diagrams appear in public section when enabled", %{conn: conn} do
      owner = fixture(:user)
      viewer = fixture(:user, show_public_diagrams: true)
      public_diagram = fixture(:diagram, visibility: :public)
      Diagrams.assign_diagram_to_user(public_diagram.id, owner.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
      {:ok, _view, html} = live(conn, ~p"/")

      # Public diagram should be visible in public section
      assert html =~ public_diagram.title
    end
  end

  describe "authorization edge cases" do
    test "non-owner cannot edit diagram", %{conn: conn} do
      owner = fixture(:user)
      other = fixture(:user)
      diagram = fixture(:diagram, visibility: :public)
      Diagrams.assign_diagram_to_user(diagram.id, owner.id, true)

      conn = Plug.Test.init_test_session(conn, %{user_id: other.id})
      {:ok, view, _html} = live(conn, ~p"/d/#{diagram.id}")

      # Non-owners should not see the edit button at all
      refute has_element?(view, "button[phx-click='edit_diagram'][phx-value-id='#{diagram.id}']")
    end

    test "non-owner cannot delete diagram", %{conn: conn} do
      owner = fixture(:user)
      other = fixture(:user)
      diagram = fixture(:diagram, visibility: :public)
      Diagrams.assign_diagram_to_user(diagram.id, owner.id, true)

      # Attempt to delete via direct event (simulating tampering)
      conn = Plug.Test.init_test_session(conn, %{user_id: other.id})
      {:ok, view, _html} = live(conn, ~p"/d/#{diagram.id}")

      # Send delete event directly
      render_click(view, "delete_diagram", %{"id" => diagram.id})

      html = render(view)
      assert html =~ "Unauthorized"

      # Diagram should still exist
      assert Diagrams.get_diagram!(diagram.id)
    end

    test "unauthenticated user cannot save filter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Save button should not be visible for unauthenticated users
      # They can't save filters because they're not logged in
      refute html =~ "Save Filter"
    end

    test "user can only delete their own filters", %{conn: conn} do
      user1 = fixture(:user)
      user2 = fixture(:user)

      # Create filter for user1
      {:ok, filter} =
        Diagrams.create_saved_filter(
          %{name: "User1 Filter", tag_filter: ["test"], is_pinned: true},
          user1.id
        )

      # User2 tries to delete user1's filter via direct event
      conn = Plug.Test.init_test_session(conn, %{user_id: user2.id})
      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "delete_filter", %{"id" => filter.id})

      html = render(view)
      assert html =~ "Unauthorized"

      # Filter should still exist
      assert Diagrams.get_saved_filter!(filter.id)
    end
  end
end
