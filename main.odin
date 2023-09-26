package main

import "core:log"
import "core:strings"
import "core:os"
import "core:slice"
import "core:math"
import "vendor:sdl2"
import "vendor:sdl2/ttf"

WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 480

Mouse :: struct {
    x, y: i32,
}

Cursor :: struct {
    x, y: i32,
}

Canvas :: struct {
    w, h: i32,
    x, y: i32,
    data: [dynamic][dynamic]u8,
}

State :: struct {
    mouse_pos: sdl2.Point,
    cursor:    Cursor,
    canvas:    Canvas,
    mouse:     Mouse,
    file:      os.Handle,
}

main :: proc() {
    state: State = {
        {0, 0},
        {0, 0},
        {0, 0, 80, 80, ---},
        {0, 0},
        ---,
    }

    // Set logger level to lowest to debug
    context.logger = log.create_console_logger(.Debug)

    // Initialize sdl2
    if err := sdl2.Init(sdl2.INIT_EVERYTHING); err < 0 {
		log.fatal("Init Error:", sdl2.GetError())
    }
    // Make sure to quit when the function returns
    defer sdl2.Quit()

    // Initialize sdlttf
    if err := ttf.Init(); err < 0 {
        log.fatal("Init Error:", ttf.GetError())
    }
    defer ttf.Quit()

    // Create the window
    win := sdl2.CreateWindow("Ascii magic", 100, 100, WINDOW_WIDTH, WINDOW_HEIGHT, sdl2.WINDOW_SHOWN)
    defer sdl2.DestroyWindow(win)

    // Create a renderer
    ren := sdl2.CreateRenderer(win, -1, {.ACCELERATED, .PRESENTVSYNC})
    if ren == nil {
        log.fatal("Couldn't create renderer")
    }
    defer sdl2.DestroyRenderer(ren)

    font_size : i32 = 48
    font := ttf.OpenFont("scientifica.ttf", font_size)
    if font == nil {
        log.fatal("Couldn't load font")
    }
    defer ttf.CloseFont(font)

    text_surface: ^sdl2.Surface
    text_texture: ^sdl2.Texture
    
    state.canvas.data = make([dynamic][dynamic]u8, 0, 0)
    unparsed_file_content := make([dynamic]u8, 0, 0)

    handle, err := os.open("./text.txt")
    if err != os.ERROR_NONE {
        log.fatal("Can't open file: ", err)
        return
    }

    file_size, _ := os.file_size(handle)
    log.debug("File size: ", file_size)

    resize(&unparsed_file_content, auto_cast(file_size))
    os.read(handle, unparsed_file_content[:])

    // image size calculations
    // state.canvas.w, state.canvas.h
     line, column: i32 = 0, 0
    for char, i in unparsed_file_content {
        column += 1
        if char == '\n' { column = 0; line += 1 }
        if state.canvas.w < column do state.canvas.w = column - 1
    }
    state.canvas.h = line + 1

    log.debug("width:", state.canvas.w, "height:", state.canvas.h)
    // setting canvas to proper size
    resize(&state.canvas.data, int(state.canvas.h))
    for i in 0..<state.canvas.h do state.canvas.data[i] = make([dynamic]u8, state.canvas.w)
    for line in state.canvas.data do slice.fill(line[:], ' ')


    // inserting image
    line, column = 0, 0
    for char in unparsed_file_content {
        column += 1
        if char == '\n' { line += 1; column = 0 }
        if !(char == '\n' || char == '\r') { state.canvas.data[line][column - 1] = char}
    }

    char_w, char_h: i32 = 0, 0

    cstr_buffer := make([dynamic]u8, state.canvas.w + 1)
    defer free(&cstr_buffer)
    cstr_buffer[state.canvas.w] = 0

    // main event loop
    main_loop: for {
        // handle inputs
        for event: sdl2.Event; sdl2.PollEvent(&event); {
            #partial switch event.type {
            case .QUIT:
                break main_loop
            case .KEYDOWN, .KEYUP:
                // Quit if ESCAPE
                if event.type == .KEYUP && event.key.keysym.sym == .ESCAPE {
                    sdl2.PushEvent(&sdl2.Event{ type = .QUIT })
                }

                if event.type == .KEYDOWN {
                    if event.key.keysym.sym == .BACKSPACE {
                        if state.cursor.x > 0 do state.canvas.data[state.cursor.y][state.cursor.x - 1] = ' '
                        if state.cursor.x - 1 >= 0 do state.cursor.x -= 1
                        else if state.cursor.y > 0 {
                            state.cursor.y -= 1
                            state.cursor.x = state.canvas.w - 1
                        }
                    }

                    if event.key.keysym.sym == .DELETE {
                        state.canvas.data[state.cursor.y][state.cursor.x] = ' '
                    }

                    if event.key.keysym.sym == .KP_MINUS && .LCTRL in sdl2.GetModState() {
                        font_size -= 2
                        ttf.SetFontSize(font, font_size)
                    }
    
                    if event.key.keysym.sym == .KP_PLUS && .LCTRL in sdl2.GetModState() {
                        font_size += 2
                        ttf.SetFontSize(font, font_size)
                    }

                    if event.key.keysym.sym == .TAB {
                        // debug dump
                        for line in state.canvas.data do log.debug(string(line[:]))
                    }
    
                    #partial switch event.key.keysym.sym {
                    case .LEFT:
                        if state.cursor.x - 1 < 0 && state.cursor.y != 0 {
                            state.cursor.x  = state.canvas.w - 1
                            state.cursor.y -= 1
                        } else if state.cursor.x > 0 do state.cursor.x -= 1
                    case .RIGHT:
                        if state.cursor.x == state.canvas.w - 1 && state.cursor.y < state.canvas.h - 1 {
                            state.cursor.x =  0
                            state.cursor.y += 1
                        } else if state.cursor.x < state.canvas.w - 1 do state.cursor.x += 1
                    case .UP:
                        if state.cursor.y != 0 do state.cursor.y -= 1
                    case .DOWN:
                        if state.cursor.y != state.canvas.h - 1 do state.cursor.y += 1
                    case .HOME: state.cursor.x = 0
                    case .END:  state.cursor.x = state.canvas.w - 1
                    }
                    // log.debug(state.cursor.x, state.cursor.y)
                }

            case .TEXTINPUT:
                composition := event.edit.text;
                cursor := event.edit.start;
                selection_len := event.edit.length;

                state.canvas.data[state.cursor.y][state.cursor.x] = composition[0]
                if state.cursor.x == state.canvas.w - 1 && state.cursor.y < state.canvas.h - 1 {
                    state.cursor.x =  0
                    state.cursor.y += 1
                } else if state.cursor.x < state.canvas.w - 1 do state.cursor.x += 1

            case .MOUSEMOTION:
                state.mouse = {event.motion.x - state.canvas.x, event.motion.y - state.canvas.y}
                state.mouse.x = clamp(state.mouse.x / char_w, 0, state.canvas.w - 1)
                state.mouse.y = clamp(state.mouse.y / char_h, 0, state.canvas.h - 1)
            case .MOUSEBUTTONDOWN:
                if event.button.button == 1 do state.cursor.x = clamp(state.mouse.x, 0, state.canvas.w - 1)
                if event.button.button == 1 do state.cursor.y = clamp(state.mouse.y, 0, state.canvas.h - 1)
            }
        }
        // clear screen
        sdl2.SetRenderDrawColor(ren, 0, 0, 0, 255);
        sdl2.RenderClear(ren)
        
        text_w, text_h: i32 = 0, 0
            
        ttf.SizeText(font, "a", &char_w, &char_h)
        sdl2.SetRenderDrawColor(ren, 255, 0, 0, 255)
        
        cursor_screen_pos: sdl2.Point = {state.cursor.x * char_w + state.canvas.x, state.cursor.y * char_h + state.canvas.y}
        cursor_rect: sdl2.Rect = {cursor_screen_pos.x, cursor_screen_pos.y, char_w, char_h}
        sdl2.RenderFillRect(ren, &cursor_rect)

        // visual mouse position on grid
        sdl2.RenderFillRect(ren, &{state.mouse.x * char_w + state.canvas.x, state.mouse.y * char_h + state.canvas.y, char_w, char_h})
        
        for _, n in state.canvas.data {
            // cstring representation
            copy_slice(cstr_buffer[:state.canvas.w], state.canvas.data[n][:])
            
            // render text
            text_surface := ttf.RenderText_Blended(font, cstring(raw_data(cstr_buffer[:])), {255, 255, 255, 255})
            defer sdl2.FreeSurface(text_surface)
            
            if text_surface != nil {
                text_w, text_h = text_surface.w, text_surface.h
                text_texture := sdl2.CreateTextureFromSurface(ren, text_surface)
                defer sdl2.DestroyTexture(text_texture)
                sdl2.RenderCopy(ren, text_texture, nil, &{state.canvas.x, i32(n) * char_h + state.canvas.y, text_w, text_h})
            }
            
            // Canvas outline
            sdl2.RenderDrawRect(ren, &{state.canvas.x, state.canvas.y, (state.canvas.w) * char_w, state.canvas.h * char_h})
        }
    
        // present rendered stuff to screen
        sdl2.RenderPresent(ren)
    }
}

