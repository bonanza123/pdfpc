/**
 * Spezialized Pdf View
 *
 * This file is part of pdfpc.
 *
 * Copyright (C) 2010-2011 Jakob Westhoff <jakob@westhoffswelt.de>
 * Copyright 2011-2012 David Vilar
 * Copyright 2012, 2015, 2017 Andreas Bilke
 * Copyright 2012, 2015 Robert Schroll
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

namespace pdfpc {
    /**
     * View spezialized to work with Pdf renderers.
     *
     * This class is mainly needed to be decorated with pdf-link-interactions
     * signals.
     *
     * By default it does not implement any further functionality.
     */
    public class View.Pdf : Gtk.DrawingArea {
        /**
         * Signal fired every time a slide is about to be left
         */
        public signal void leaving_slide(int from, int to);

        /**
         * Signal fired every time a slide is entered
         */
        public signal void entering_slide(int slide_number);

        /**
         * Renderer to be used for rendering the slides
         */
        protected Renderer.Pdf renderer;

        /**
         * Return the metadata object
         */
        public Metadata.Pdf get_metadata() {
            return this.renderer.metadata;
        }

        /**
         * Signal emitted every time a precached slide has been created
         *
         * This signal should be emitted slide_count number of times during a
         * precaching cycle.
         */
        public signal void slide_prerendered();

        /**
         * Signal emitted when the precaching cycle is complete
         */
        public signal void prerendering_completed();

        /**
         * Signal emitted when the precaching cycle just started
         */
        public signal void prerendering_started();

        /**
         * Signal emitted on toggling the freeze state
         */
        public signal void freeze_toggled(bool frozen);

        /**
         * The currently displayed slide
         */
        protected int current_slide_number;

        /**
         * Whether the view should remain black
         */
        public bool disabled;

        /**
         * The number of slides in the presentation
         */
        protected int n_slides {
            get {
                return (int) this.get_metadata().get_slide_count();
            }
        }

        /**
         * List to store all associated behaviours
         */
        protected GLib.List<View.Behaviour.Base> behaviours = new GLib.List<View.Behaviour.Base>();

        /**
         * GDK scale factor
         */
        protected int gdk_scale = 1;

        /**
         * The area of the pdf which shall be displayed
         */
        protected Metadata.Area area;

        /**
         * Default constructor restricted to Pdf renderers as input parameter
         */
        public Pdf(Renderer.Pdf renderer, Metadata.Area area,
            bool clickable_links, PresentationController controller,
            int gdk_scale_factor) {
            this.renderer = renderer;
            this.gdk_scale = gdk_scale_factor;
            this.area = area;

            this.current_slide_number = 0;

            this.add_events(Gdk.EventMask.STRUCTURE_MASK);

            if (clickable_links) {
                // Enable the PDFLink Behaviour by default on PDF Views
                this.associate_behaviour(new View.Behaviour.PdfLink());
            }
        }

        /**
         * Create a new Pdf view from a Fullscreen window instance
         *
         * This is a convenience constructor which automatically creates a full
         * metadata and rendering chain to be used with the pdf view.
         */
        public Pdf.from_fullscreen(Window.Fullscreen window,
            Metadata.Area area, bool clickable_links) {
            var controller = window.controller;
            var metadata = controller.metadata;

            // will be resized on first use
            var renderer = metadata.renderer;

            this(renderer, area, clickable_links, controller, window.gdk_scale);
        }

        /**
         * Convert an arbitrary Poppler.Rectangle struct into a Gdk.Rectangle
         * struct taking into account the measurement differences between pdf
         * space and screen space.
         */
        public Gdk.Rectangle convert_poppler_rectangle_to_gdk_rectangle(
            Poppler.Rectangle poppler_rectangle) {
            Gdk.Rectangle gdk_rectangle = Gdk.Rectangle();

            Gtk.Allocation allocation;
            this.get_allocation(out allocation);

            // We need the page dimensions for coordinate conversion between
            // pdf coordinates and screen coordinates
            var metadata = this.get_metadata();
            gdk_rectangle.x = (int) Math.ceil((poppler_rectangle.x1 / metadata.get_page_width()) *
                allocation.width );
            gdk_rectangle.width = (int) Math.floor(((poppler_rectangle.x2 - poppler_rectangle.x1) /
                metadata.get_page_width()) * allocation.width);

            // Gdk has its coordinate origin in the upper left, while Poppler
            // has its origin in the lower left.
            gdk_rectangle.y = (int) Math.ceil(((metadata.get_page_height() - poppler_rectangle.y2) /
                metadata.get_page_height()) * allocation.height);
            gdk_rectangle.height = (int) Math.floor(((poppler_rectangle.y2 - poppler_rectangle.y1) /
                metadata.get_page_height()) * allocation.height);

            return gdk_rectangle;
        }

        /**
         * Associate a new Behaviour with this View
         *
         * The implementation supports an arbitrary amount of different
         * behaviours.
         */
        public void associate_behaviour(Behaviour.Base behaviour) {
            this.behaviours.append(behaviour);
            try {
                behaviour.associate(this);
            } catch(Behaviour.AssociationError e) {
                GLib.printerr("Behaviour association failure: %s\n", e.message);
                Process.exit(1);
            }
        }

        /**
         * Display a specific slide number
         *
         * If the slide number does not exist a
         * RenderError.SLIDE_DOES_NOT_EXIST is thrown
         */
        public void display(int slide_number)
            throws Renderer.RenderError {

            if (this.n_slides == 0) {
                return;
            }

            // If the slide is out of bounds render the outer most slide on
            // each side of the document.
            if (slide_number < 0) {
                slide_number = 0;
            } else if (slide_number >= this.n_slides + 1) {
                slide_number = this.n_slides - 1;
            }

            // Notify all listeners
            this.leaving_slide(this.current_slide_number, slide_number);

            this.current_slide_number = slide_number;

            // Have Gtk update the widget
            this.queue_draw();

            this.entering_slide(this.current_slide_number);
        }

        /**
         * Return pixel dimensions of the widget
         */
        protected void get_pixel_dimensions(out int width, out int height) {
            Gtk.Allocation allocation;
            this.get_allocation(out allocation);
            width = allocation.width*this.gdk_scale;
            height = allocation.height*this.gdk_scale;
        }

        /**
         * This method is called by Gdk every time the widget needs to be redrawn.
         *
         * The implementation does a simple blit from the internal pixmap to
         * the window surface.
         */
        public override bool draw(Cairo.Context cr) {
            var metadata = this.get_metadata();
            if (!metadata.is_ready) {
                return true;
            }

            int width, height;
            this.get_pixel_dimensions(out width, out height);

            // not ready yet
            if (height <= 1 || width <= 1) {
                return true;
            }

            Cairo.ImageSurface current_slide;

            try {
                // An exception is thrown here, if the slide can not be rendered.
                if (this.current_slide_number < this.n_slides && !this.disabled) {
                    current_slide =
                        this.renderer.render_to_surface(this.current_slide_number,
                            this.area, width, height);
                } else {
                    current_slide = this.renderer.fade_to_black(width, height);
                }

                cr.scale((1.0/this.gdk_scale), (1.0/this.gdk_scale));
                cr.set_source_surface(current_slide, 0, 0);
                cr.rectangle(0, 0, current_slide.get_width(),
                    current_slide.get_height());
                cr.fill();
            } catch (Renderer.RenderError e) {
            }

            // We are the only ones drawing on this context; skip everything
            // else.
            return true;
        }
    }
}
