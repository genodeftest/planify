/*
* Copyright © 2023 Alain M. (https://github.com/alainm23/planify)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 3 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Alain M. <alainmh23@gmail.com>
*/

public class MainWindow : Adw.ApplicationWindow {
	public weak Planify app { get; construct; }

	private Layouts.Sidebar sidebar;
	private Gtk.Stack views_stack;
	private Adw.OverlaySplitView overlay_split_view;
	private Gtk.MenuButton settings_button;
	private Layouts.ItemSidebarView item_sidebar_view;
	private Gtk.Button fake_button;

	public Services.ActionManager action_manager;

	public MainWindow (Planify application) {
		Object (
			application: application,
			app: application,
			icon_name: Build.APPLICATION_ID,
			title: "Planify",
			width_request: 450,
			height_request: 480
		);
	}

	static construct {
		weak Gtk.IconTheme default_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
		default_theme.add_resource_path ("/io/github/alainm23/planify/");
	}

	construct {
		if (Build.PROFILE == "development") {
			add_css_class ("devel");
		}

		action_manager = new Services.ActionManager (app, this);

		Services.DBusServer.get_default ().item_added.connect ((id) => {
			var item = Services.Database.get_default ().get_item_by_id (id);
			Services.Database.get_default ().add_item (item);
		});

		var settings_popover = build_menu_app ();

		fake_button = new Gtk.Button () {
			visible = false
		};

		settings_button = new Gtk.MenuButton () {
			css_classes = { "flat" },
			popover = settings_popover,
			child = new Gtk.Image.from_icon_name ("open-menu-symbolic")
		};

		var search_button = new Gtk.Button.from_icon_name ("edit-find-symbolic") {
			tooltip_markup = Util.get_default ().markup_accel_tooltip (_("Open Quick Find"), "Ctrl+F"),
			css_classes = { "flat" }
		};

		var sidebar_header = new Adw.HeaderBar () {
			title_widget = new Gtk.Label (null),
			hexpand = true
		};

		sidebar_header.add_css_class ("flat");
		sidebar_header.pack_end (settings_button);
		sidebar_header.pack_end (search_button);
		sidebar_header.pack_end (fake_button);

		sidebar = new Layouts.Sidebar ();

		var sidebar_view = new Adw.ToolbarView ();
		sidebar_view.add_top_bar (sidebar_header);
		sidebar_view.content = sidebar;

		views_stack = new Gtk.Stack () {
			hexpand = true,
			vexpand = true,
			transition_type = Gtk.StackTransitionType.SLIDE_RIGHT
		};

		item_sidebar_view = new Layouts.ItemSidebarView ();
		
		var views_split_view = new Adw.OverlaySplitView () {
			sidebar_position = Gtk.PackType.END,
			collapsed = true,
			max_sidebar_width = 375,
			content = views_stack,
			sidebar = item_sidebar_view
		};

		var toast_overlay = new Adw.ToastOverlay () {
			child = views_split_view
		};

		overlay_split_view = new Adw.OverlaySplitView ();
		overlay_split_view.content = toast_overlay;
		overlay_split_view.sidebar = sidebar_view;
		
		var breakpoint = new Adw.Breakpoint (Adw.BreakpointCondition.parse ("max-width: 800sp"));
		breakpoint.add_setter (overlay_split_view, "collapsed", true);

		add_breakpoint (breakpoint);
		content = overlay_split_view;

		Services.Settings.get_default ().settings.bind ("pane-position", overlay_split_view, "min_sidebar_width", GLib.SettingsBindFlags.DEFAULT);
		Services.Settings.get_default ().settings.bind ("slim-mode", overlay_split_view, "show_sidebar", GLib.SettingsBindFlags.DEFAULT);
		Services.Settings.get_default ().settings.bind ("mobile-mode", overlay_split_view, "collapsed", GLib.SettingsBindFlags.DEFAULT);

		Timeout.add (250, () => {
			init_backend ();
			overlay_split_view.show_sidebar = true;
			fake_button.grab_focus ();
			return GLib.Source.REMOVE;
		});

		var granite_settings = Granite.Settings.get_default ();
		granite_settings.notify["prefers-color-scheme"].connect (() => {
			if (Services.Settings.get_default ().settings.get_boolean ("system-appearance")) {
				Services.Settings.get_default ().settings.set_boolean (
					"dark-mode",
					granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK
					);
				Util.get_default ().update_theme ();
			}
		});

		Services.Settings.get_default ().settings.changed.connect ((key) => {
			if (key == "system-appearance") {
				Services.Settings.get_default ().settings.set_boolean (
					"dark-mode",
					granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK
					);
				Util.get_default ().update_theme ();
			} else if (key == "appearance" || key == "dark-mode") {
				Util.get_default ().update_theme ();
			} else if (key == "run-in-background") {
				//  set_hide_on_close (Services.Settings.get_default ().settings.get_boolean ("run-in-background"));
			} else if (key == "run-on-startup") {
				bool active = Services.Settings.get_default ().settings.get_boolean ("run-on-startup");

				if (active) {
					Planify.instance.ask_for_background.begin (Xdp.BackgroundFlags.AUTOSTART, (obj, res) => {
						if (Planify.instance.ask_for_background.end (res)) {
							Services.Settings.get_default ().settings.set_boolean ("run-on-startup", true);
						} else {
							Services.Settings.get_default ().settings.set_boolean ("run-on-startup", false);
						}
					});
				} else {
					Planify.instance.ask_for_background.begin (Xdp.BackgroundFlags.NONE, (obj, res) => {
						if (Planify.instance.ask_for_background.end (res)) {
							Services.Settings.get_default ().settings.set_boolean ("run-on-startup", false);
						} else {
							Services.Settings.get_default ().settings.set_boolean ("run-on-startup", false);
						}
					});
				}
			} else if (key == "mobile-mode") {
				Services.EventBus.get_default ().mobile_mode = Services.Settings.get_default ().settings.get_boolean ("mobile-mode");
			}
		});

		Services.EventBus.get_default ().pane_selected.connect ((pane_type, id) => {
			Services.EventBus.get_default ().unselect_all ();

			if (pane_type == PaneType.PROJECT) {
				add_project_view (Services.Database.get_default ().get_project (id));
			} else if (pane_type == PaneType.FILTER) {
				if (id == FilterType.INBOX.to_string ()) {
					add_inbox_view ();
				} else if (id == FilterType.TODAY.to_string ()) {
					add_today_view ();
				} else if (id == FilterType.SCHEDULED.to_string ()) {
					add_scheduled_view ();
				} else if (id == FilterType.PINBOARD.to_string ()) {
					add_filter_view (Objects.Filters.Pinboard.get_default ());
				} else if (id == FilterType.LABELS.to_string ()) {
					add_labels_view ();
				} else if (id.has_prefix ("priority")) {
					add_priority_view (id);
				} else if (id == FilterType.COMPLETED.to_string ()) {
					add_filter_view (Objects.Filters.Completed.get_default ());
				} else if (id == "tomorrow-view") {
					add_filter_view (Objects.Filters.Tomorrow.get_default ());
				} else if (id == "anytime-view") {
					add_filter_view (Objects.Filters.Anytime.get_default ());
				} else if (id == "repeating-view") {
					add_filter_view (Objects.Filters.Repeating.get_default ());
				} else if (id == "unlabeled-view") {
					add_filter_view (Objects.Filters.Unlabeled.get_default ());
				}
			} else if (pane_type == PaneType.LABEL) {
				add_label_view (id);
			}

			if (overlay_split_view.collapsed) {
				overlay_split_view.show_sidebar = false;
			}
		});

		Services.EventBus.get_default ().send_notification.connect ((toast) => {
			toast_overlay.add_toast (toast);
		});

		search_button.clicked.connect (() => {
			(new Dialogs.QuickFind.QuickFind ()).show ();
		});

		var event_controller_key = new Gtk.EventControllerKey ();
		((Gtk.Widget) this).add_controller (event_controller_key);
		event_controller_key.key_pressed.connect ((keyval, keycode, state) => {
			if (keyval == 65507) {
				Services.EventBus.get_default ().ctrl_pressed = true;
			}

			if (keyval == 65513) {
				Services.EventBus.get_default ().alt_pressed = true;
            }

			return false;
        });
		
        event_controller_key.key_released.connect ((keyval, keycode, state) => {
            if (keyval == 65507) {
				Services.EventBus.get_default ().ctrl_pressed = false;
			}

			if (keyval == 65513) {
				Services.EventBus.get_default ().alt_pressed = false;
            }
        });

		Services.EventBus.get_default ().open_item.connect ((item) => {
			if (views_split_view.show_sidebar) {
				views_split_view.show_sidebar = false;
				Timeout.add (275, () => {
					views_split_view.show_sidebar = true;
					item_sidebar_view.present_item (item);
					return GLib.Source.REMOVE;
				});
			} else {
				views_split_view.show_sidebar = true;
				item_sidebar_view.present_item (item);
			}
		});

		Services.EventBus.get_default ().close_item.connect (() => {
			views_split_view.show_sidebar = false;
		});

		views_split_view.notify["show-sidebar"].connect (() => {
			if (!views_split_view.show_sidebar) {
				item_sidebar_view.disconnect_all ();
				fake_button.grab_focus ();
			}
		});
	}

	public void show_hide_sidebar () {
		overlay_split_view.show_sidebar = !overlay_split_view.show_sidebar;
	}

	private void init_backend () {
		Services.Database.get_default ().init_database ();

		if (Services.Database.get_default ().is_database_empty ()) {
			Util.get_default ().create_inbox_project ();
			Util.get_default ().create_tutorial_project ();
			Util.get_default ().create_default_labels ();
		}

		sidebar.init ();

		Services.Notification.get_default ();
		Services.TimeMonitor.get_default ().init_timeout ();

		go_homepage ();

		Services.Database.get_default ().project_deleted.connect (valid_view_removed);
		Services.Database.get_default ().project_archived.connect (valid_view_removed);

		if (Services.Todoist.get_default ().is_logged_in ()) {
			Timeout.add (Constants.SYNC_TIMEOUT, () => {
				Services.Todoist.get_default ().run_server ();
				return GLib.Source.REMOVE;
			});
		}

		if (Services.CalDAV.Core.get_default ().is_logged_in ()) {
			Timeout.add (Constants.SYNC_TIMEOUT, () => {
				Services.CalDAV.Core.get_default ().run_server ();
				return GLib.Source.REMOVE;
			});
		}
	}

	private void add_inbox_view () {
		add_project_view (
			Services.Database.get_default ().get_project (
				Services.Settings.get_default ().settings.get_string ("local-inbox-project-id")
			)
		);
	}

	public Views.Project add_project_view (Objects.Project project) {
		Views.Project? project_view;
		project_view = (Views.Project) views_stack.get_child_by_name (project.view_id);
		if (project_view == null) {
			project_view = new Views.Project (project);
			views_stack.add_named (project_view, project.view_id);
		}

		views_stack.set_visible_child_name (project.view_id);
		return project_view;
	}

	public void add_today_view () {
		Views.Today? today_view;
		today_view = (Views.Today) views_stack.get_child_by_name ("today-view");
		if (today_view == null) {
			today_view = new Views.Today ();
			views_stack.add_named (today_view, "today-view");
		}

		views_stack.set_visible_child_name ("today-view");
	}

	public void add_scheduled_view () {
		Views.Scheduled.Scheduled? scheduled_view;
		scheduled_view = (Views.Scheduled.Scheduled) views_stack.get_child_by_name ("scheduled-view");
		if (scheduled_view == null) {
			scheduled_view = new Views.Scheduled.Scheduled ();
			views_stack.add_named (scheduled_view, "scheduled-view");
		}

		views_stack.set_visible_child_name ("scheduled-view");
	}

	public void add_labels_view () {		
		Views.Labels? labels_view;
		labels_view = (Views.Labels) views_stack.get_child_by_name ("labels-view");
		if (labels_view == null) {
			labels_view = new Views.Labels ();
			views_stack.add_named (labels_view, "labels-view");
		}

		views_stack.set_visible_child_name ("labels-view");
	}

	private void add_label_view (string id) {
		Views.Label? label_view;
		label_view = (Views.Label) views_stack.get_child_by_name ("label-view");
		if (label_view == null) {
			label_view = new Views.Label ();
			views_stack.add_named (label_view, "label-view");
		}

		label_view.label = Services.Database.get_default ().get_label (id);
		views_stack.set_visible_child_name ("label-view");
	}

	public void add_priority_view (string view_id) {
		Views.Filter? filter_view;
		filter_view = (Views.Filter) views_stack.get_child_by_name (view_id);
		if (filter_view == null) {
			filter_view = new Views.Filter ();
			views_stack.add_named (filter_view, view_id);
		}

		filter_view.filter = Util.get_default ().get_priority_filter (view_id);
		views_stack.set_visible_child_name (view_id);
	}

	private void add_filter_view (Objects.BaseObject base_object) {
		Views.Filter? filter_view;
		filter_view = (Views.Filter) views_stack.get_child_by_name (base_object.view_id);
		if (filter_view == null) {
			filter_view = new Views.Filter ();
			filter_view.filter = base_object;
			views_stack.add_named (filter_view, base_object.view_id);
		}

		views_stack.set_visible_child_name (base_object.view_id);
	}

	public void go_homepage () {
		Services.EventBus.get_default ().pane_selected (
			PaneType.FILTER,
			Util.get_default ().get_filter ().to_string ()
		);
	}

	public void view_item (string id) {
		var item = Services.Database.get_default ().get_item_by_id (id);
		Services.EventBus.get_default ().pane_selected (PaneType.PROJECT, item.project_id);
	}

	public void valid_view_removed (Objects.Project project) {
		Views.Project? project_view;
		project_view = (Views.Project) views_stack.get_child_by_name (project.view_id);
		if (project_view != null) {
			views_stack.remove (project_view);
			go_homepage ();
		}
	}

	public void add_task_action (string content = "") {
		if (views_stack.visible_child_name.has_prefix ("project")) {
			Views.Project? project_view = (Views.Project) views_stack.visible_child;
			if (project_view != null) {
				project_view.prepare_new_item (content);
			}
		} else if (views_stack.visible_child_name.has_prefix ("today-view")) {
			Views.Today? today_view = (Views.Today) views_stack.visible_child;
			if (today_view != null) {
				today_view.prepare_new_item (content);
			}
		} else if (views_stack.visible_child_name.has_prefix ("scheduled-view")) {
			Views.Scheduled.Scheduled? scheduled_view = (Views.Scheduled.Scheduled) views_stack.visible_child;
			if (scheduled_view != null) {
			    scheduled_view.prepare_new_item (content);
			}
		} else if (views_stack.visible_child_name.has_prefix ("labels-view")) {
			var dialog = new Dialogs.QuickAdd ();
			dialog.update_content (content);
			dialog.show ();
		} else if (views_stack.visible_child_name.has_prefix ("label-view")) {
			Views.Label? label_view = (Views.Label) views_stack.visible_child;
			if (label_view != null) {
			    label_view.prepare_new_item (content);
			}
		} else {
			Views.Filter? filter_view = (Views.Filter) views_stack.visible_child;
			if (filter_view != null) {
				filter_view.prepare_new_item (content);
			} else {
				var dialog = new Dialogs.QuickAdd ();
				dialog.update_content (content);
				dialog.show ();
			}
		}
	}

	public void new_section_action () {
		if (!views_stack.visible_child_name.has_prefix ("project")) {
			return;
		}

		Views.Project? project_view = (Views.Project) views_stack.visible_child;
		if (project_view != null) {
			project_view.prepare_new_section ();
		}
	}

	private Gtk.Popover build_menu_app () {
		var preferences_item = new Widgets.ContextMenu.MenuItem (_("Preferences"));
		preferences_item.secondary_text = "Ctrl+,";

		var keyboard_shortcuts_item = new Widgets.ContextMenu.MenuItem (_("Keyboard Shortcuts"));
		keyboard_shortcuts_item.secondary_text = "F1";

		var whatsnew_item = new Widgets.ContextMenu.MenuItem (_("What's New"));
		var about_item = new Widgets.ContextMenu.MenuItem (_("About Planify"));
		var archive_item = new Widgets.ContextMenu.MenuItem (_("Archived Projects"));

		var menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
		menu_box.margin_top = menu_box.margin_bottom = 3;
		menu_box.append (preferences_item);
		menu_box.append (whatsnew_item);
		menu_box.append (new Widgets.ContextMenu.MenuSeparator ());
		menu_box.append (archive_item);
		menu_box.append (new Widgets.ContextMenu.MenuSeparator ());
		menu_box.append (keyboard_shortcuts_item);
		menu_box.append (about_item);

		var popover = new Gtk.Popover () {
			has_arrow = true,
			child = menu_box,
			width_request = 250,
			position = Gtk.PositionType.BOTTOM
		};

		preferences_item.clicked.connect (() => {
			popover.popdown ();

			var dialog = new Dialogs.Preferences.PreferencesWindow ();
			dialog.show ();
		});

		whatsnew_item.clicked.connect (() => {
			popover.popdown ();

			var dialog = new Dialogs.WhatsNew ();
			dialog.show ();
		});

		about_item.clicked.connect (() => {
			popover.popdown ();
			about_dialog ();
		});

		keyboard_shortcuts_item.clicked.connect (() => {
			popover.popdown ();
			open_shortcuts_window ();
		});

		archive_item.clicked.connect (() => {
			popover.popdown ();
			var dialog = new Dialogs.ManageProjects ();
			dialog.show ();
		});

		return popover;
	}

	public void open_shortcuts_window () {
		try {
			var build = new Gtk.Builder ();
			build.add_from_resource ("/io/github/alainm23/planify/shortcuts.ui");
			var window = (Gtk.ShortcutsWindow) build.get_object ("shortcuts-planify");
			window.set_transient_for (this);
			window.show ();
		} catch (Error e) {
			warning ("Failed to open shortcuts window: %s\n", e.message);
		}
	}

	private void about_dialog () {
		Adw.AboutWindow dialog;

		if (Build.PROFILE == "development") {
			dialog = new Adw.AboutWindow ();
		} else {
			dialog = new Adw.AboutWindow.from_appdata (
				"/io/github/alainm23/planify/" + Build.APPLICATION_ID + ".appdata.xml.in.in", Build.VERSION
			);
		}

		dialog.transient_for = (Gtk.Window) Planify.instance.main_window;
		dialog.modal = true;
		dialog.application_icon = Build.APPLICATION_ID;
		dialog.application_name = "Planify";
		dialog.developer_name = "Alain";
		dialog.designers = { "Alain" };
		dialog.website = "https://github.com/alainm23/planify";
		dialog.developers = { "Alain" };
		dialog.issue_url = "https://github.com/alainm23/planify/issues";

		dialog.show ();
	}
}
