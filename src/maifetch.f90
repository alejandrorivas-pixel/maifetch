module maifetch_app
  use iso_fortran_env, only: error_unit
  implicit none

  character(len=*), parameter :: base_url = "https://maitea.app"

  type :: config
    character(:), allocatable :: access_token
    character(:), allocatable :: config_file
    character(:), allocatable :: profiles_fixture
    character(:), allocatable :: plays_fixture
    integer :: logo_size = 20
    integer :: score_count = 4
    logical :: no_color = .false.
  end type config

  type :: json_object
    character(:), allocatable :: text
  end type json_object

  type :: line_item
    character(:), allocatable :: text
  end type line_item

contains
  subroutine die(message)
    character(len=*), intent(in) :: message
    write(error_unit, '(A)') trim(message)
    error stop 1
  end subroutine die

  function env_value(name) result(value)
    character(len=*), intent(in) :: name
    character(:), allocatable :: value
    integer :: needed, status

    call get_environment_variable(name, length=needed, status=status)
    if (status /= 0 .or. needed <= 0) then
      value = ""
      return
    end if

    allocate(character(len=needed) :: value)
    call get_environment_variable(name, value=value, status=status)
    if (status /= 0) value = ""
  end function env_value

  function file_exists(path) result(exists)
    character(len=*), intent(in) :: path
    logical :: exists
    inquire(file=trim(path), exist=exists)
  end function file_exists

  function default_config_path() result(path)
    character(:), allocatable :: path
    character(:), allocatable :: home, appdata, xdg

    home = env_value("HOME")
    appdata = env_value("APPDATA")
    xdg = env_value("XDG_CONFIG_HOME")

    if (len_trim(appdata) > 0) then
      path = trim(appdata) // "/maifetch.json"
    else if (len_trim(xdg) > 0) then
      path = trim(xdg) // "/maifetch.json"
    else if (len_trim(home) > 0 .and. &
        file_exists(trim(home) // "/Library/Application Support")) then
      path = trim(home) // "/Library/Application Support/maifetch.json"
    else if (len_trim(home) > 0) then
      path = trim(home) // "/.config/maifetch.json"
    else
      path = ".config/maifetch.json"
    end if
  end function default_config_path

  function starts_with(text, prefix) result(matches)
    character(len=*), intent(in) :: text, prefix
    logical :: matches
    matches = len(text) >= len(prefix)
    if (matches) matches = text(1:len(prefix)) == prefix
  end function starts_with

  function after_equal(arg) result(value)
    character(len=*), intent(in) :: arg
    character(:), allocatable :: value
    integer :: pos

    pos = index(arg, "=")
    if (pos == 0) then
      value = ""
    else
      value = arg(pos + 1:)
    end if
  end function after_equal

  function parse_int(text, fallback) result(value)
    character(len=*), intent(in) :: text
    integer, intent(in) :: fallback
    integer :: value, ios

    if (len_trim(text) == 0) then
      value = fallback
      return
    end if

    read(text, *, iostat=ios) value
    if (ios /= 0) value = fallback
  end function parse_int

  subroutine print_help()
    print '(A)', "Usage: maifetch [options]"
    print '(A)', ""
    print '(A)', "Options:"
    print '(A)', "  -a, --access-token TOKEN    Access token for the MaiTea account"
    print '(A)', "  -t TOKEN                    Access token for the MaiTea account"
    print '(A)', "  -l, --logo-size SIZE        Size of the ASCII logo (<1 disables)"
    print '(A)', "  -s, --score-count COUNT     Amount of recent scores to show (max 12)"
    print '(A)', "  -c, --config-file FILE      Config file to use"
    print '(A)', "      --profiles-fixture FILE Read profiles JSON from a fixture file"
    print '(A)', "      --plays-fixture FILE    Read plays JSON from a fixture file"
    print '(A)', "      --no-color              Disable ANSI colors"
    print '(A)', "  -h, --help                  Show this help"
  end subroutine print_help

  subroutine read_json_config(path, token, logo_size, score_count)
    character(len=*), intent(in) :: path
    character(:), allocatable, intent(inout) :: token
    integer, intent(inout) :: logo_size, score_count
    character(:), allocatable :: json, json_token

    if (.not. file_exists(path)) return

    json = read_file(path)
    json_token = json_string(json, "accessToken")
    if (len_trim(json_token) > 0) token = json_token
    logo_size = json_int(json, "logoSize", logo_size)
    score_count = json_int(json, "scoreCount", score_count)
  end subroutine read_json_config

  subroutine load_config(cfg)
    type(config), intent(out) :: cfg
    character(:), allocatable :: arg, next, cli_token, cli_config
    character(:), allocatable :: env_token, env_logo, env_scores
    integer :: i, argc, cli_logo, cli_scores
    logical :: has_cli_logo, has_cli_scores

    cfg%config_file = default_config_path()
    cfg%access_token = ""
    cfg%profiles_fixture = ""
    cfg%plays_fixture = ""
    cli_token = ""
    cli_config = ""
    cli_logo = cfg%logo_size
    cli_scores = cfg%score_count
    has_cli_logo = .false.
    has_cli_scores = .false.

    argc = command_argument_count()
    i = 1
    do while (i <= argc)
      call get_command_argument_alloc(i, arg)
      select case (trim(arg))
      case ("-h", "--help")
        call print_help()
        stop
      case ("--no-color")
        cfg%no_color = .true.
      case ("-a", "-t", "--access-token")
        call require_next(i, argc, trim(arg), next)
        cli_token = next
        i = i + 1
      case ("-l", "--logo-size")
        call require_next(i, argc, trim(arg), next)
        cli_logo = parse_int(next, cfg%logo_size)
        has_cli_logo = .true.
        i = i + 1
      case ("-s", "--score-count")
        call require_next(i, argc, trim(arg), next)
        cli_scores = parse_int(next, cfg%score_count)
        has_cli_scores = .true.
        i = i + 1
      case ("-c", "--config-file")
        call require_next(i, argc, trim(arg), next)
        cli_config = next
        i = i + 1
      case ("--profiles-fixture")
        call require_next(i, argc, trim(arg), next)
        cfg%profiles_fixture = next
        i = i + 1
      case ("--plays-fixture")
        call require_next(i, argc, trim(arg), next)
        cfg%plays_fixture = next
        i = i + 1
      case default
        if (starts_with(arg, "--access-token=")) then
          cli_token = after_equal(arg)
        else if (starts_with(arg, "--logo-size=")) then
          cli_logo = parse_int(after_equal(arg), cfg%logo_size)
          has_cli_logo = .true.
        else if (starts_with(arg, "--score-count=")) then
          cli_scores = parse_int(after_equal(arg), cfg%score_count)
          has_cli_scores = .true.
        else if (starts_with(arg, "--config-file=")) then
          cli_config = after_equal(arg)
        else if (starts_with(arg, "--profiles-fixture=")) then
          cfg%profiles_fixture = after_equal(arg)
        else if (starts_with(arg, "--plays-fixture=")) then
          cfg%plays_fixture = after_equal(arg)
        else
          call die("unknown argument: " // trim(arg))
        end if
      end select
      i = i + 1
    end do

    if (len_trim(cli_config) > 0) cfg%config_file = cli_config
    cfg%access_token = ""
    call read_json_config(cfg%config_file, cfg%access_token, &
      cfg%logo_size, cfg%score_count)

    env_token = env_value("MAITEA_TOKEN")
    env_logo = env_value("MAITEA_LOGO_SIZE")
    env_scores = env_value("MAITEA_SCORE_COUNT")

    if (len_trim(env_token) > 0) cfg%access_token = env_token
    if (len_trim(env_logo) > 0) cfg%logo_size = parse_int(env_logo, cfg%logo_size)
    if (len_trim(env_scores) > 0) then
      cfg%score_count = parse_int(env_scores, cfg%score_count)
    end if

    if (len_trim(cli_token) > 0) cfg%access_token = cli_token
    if (has_cli_logo) cfg%logo_size = cli_logo
    if (has_cli_scores) cfg%score_count = cli_scores

    if (cfg%score_count > 12) call die("score count cannot be higher than 12")
    if ((len_trim(cfg%profiles_fixture) == 0 .or. &
        len_trim(cfg%plays_fixture) == 0) .and. &
        len_trim(cfg%access_token) == 0) then
      call die("access token is required")
    end if
  end subroutine load_config

  subroutine require_next(i, argc, flag, value)
    integer, intent(in) :: i, argc
    character(len=*), intent(in) :: flag
    character(:), allocatable, intent(out) :: value

    if (i >= argc) call die("missing value for " // trim(flag))
    call get_command_argument_alloc(i + 1, value)
  end subroutine require_next

  subroutine get_command_argument_alloc(index, value)
    integer, intent(in) :: index
    character(:), allocatable, intent(out) :: value
    integer :: needed

    call get_command_argument(index, length=needed)
    allocate(character(len=needed) :: value)
    call get_command_argument(index, value=value)
  end subroutine get_command_argument_alloc

  function read_file(path) result(contents)
    character(len=*), intent(in) :: path
    character(:), allocatable :: contents
    integer :: unit, ios, file_size

    inquire(file=trim(path), size=file_size)
    if (file_size < 0) call die("could not stat file: " // trim(path))
    allocate(character(len=file_size) :: contents)

    open(newunit=unit, file=trim(path), access="stream", form="unformatted", &
      action="read", iostat=ios)
    if (ios /= 0) call die("could not open file: " // trim(path))
    read(unit, iostat=ios) contents
    close(unit)
    if (ios /= 0) call die("could not read file: " // trim(path))
  end function read_file

  function json_string(json, key) result(value)
    character(len=*), intent(in) :: json, key
    character(:), allocatable :: value
    character(:), allocatable :: pattern
    integer :: key_pos, pos, start_pos, stop_pos
    logical :: escaped

    value = ""
    pattern = '"' // key // '"'
    key_pos = index(json, pattern)
    if (key_pos == 0) return

    pos = key_pos + len(pattern)
    pos = pos + index(json(pos:), ":")
    if (pos <= key_pos + len(pattern)) return
    call skip_ws(json, pos)

    if (starts_with(json(pos:), "null")) return
    if (json(pos:pos) /= '"') return

    start_pos = pos + 1
    stop_pos = start_pos
    escaped = .false.
    do while (stop_pos <= len(json))
      if (escaped) then
        escaped = .false.
      else if (json(stop_pos:stop_pos) == "\") then
        escaped = .true.
      else if (json(stop_pos:stop_pos) == '"') then
        value = json(start_pos:stop_pos - 1)
        return
      end if
      stop_pos = stop_pos + 1
    end do
  end function json_string

  function json_int(json, key, fallback) result(value)
    character(len=*), intent(in) :: json, key
    integer, intent(in) :: fallback
    integer :: value, key_pos, pos, end_pos, ios
    character(:), allocatable :: pattern, raw

    value = fallback
    pattern = '"' // key // '"'
    key_pos = index(json, pattern)
    if (key_pos == 0) return

    pos = key_pos + len(pattern)
    pos = pos + index(json(pos:), ":")
    if (pos <= key_pos + len(pattern)) return
    call skip_ws(json, pos)

    end_pos = pos
    do while (end_pos <= len(json))
      if (index("-+0123456789", json(end_pos:end_pos)) == 0) exit
      end_pos = end_pos + 1
    end do

    if (end_pos <= pos) return
    raw = json(pos:end_pos - 1)
    read(raw, *, iostat=ios) value
    if (ios /= 0) value = fallback
  end function json_int

  subroutine skip_ws(text, pos)
    character(len=*), intent(in) :: text
    integer, intent(inout) :: pos

    do while (pos <= len(text))
      if (index(" " // achar(9) // achar(10) // achar(13), text(pos:pos)) == 0) exit
      pos = pos + 1
    end do
  end subroutine skip_ws

  subroutine parse_data_objects(json, objects)
    character(len=*), intent(in) :: json
    type(json_object), allocatable, intent(out) :: objects(:)
    integer :: data_pos, bracket_rel, i, start_pos, depth
    logical :: in_string, escaped

    allocate(objects(0))
    data_pos = index(json, '"data"')
    if (data_pos == 0) call die("response did not include a data array")
    bracket_rel = index(json(data_pos:), "[")
    if (bracket_rel == 0) call die("response data was not an array")

    i = data_pos + bracket_rel
    depth = 0
    start_pos = 0
    in_string = .false.
    escaped = .false.

    do while (i <= len(json))
      if (in_string) then
        if (escaped) then
          escaped = .false.
        else if (json(i:i) == "\") then
          escaped = .true.
        else if (json(i:i) == '"') then
          in_string = .false.
        end if
      else
        select case (json(i:i))
        case ('"')
          in_string = .true.
        case ("{")
          if (depth == 0) start_pos = i
          depth = depth + 1
        case ("}")
          depth = depth - 1
          if (depth == 0 .and. start_pos > 0) then
            call append_object(objects, json(start_pos:i))
            start_pos = 0
          end if
        case ("]")
          if (depth == 0) exit
        end select
      end if
      i = i + 1
    end do
  end subroutine parse_data_objects

  subroutine append_object(objects, text)
    type(json_object), allocatable, intent(inout) :: objects(:)
    character(len=*), intent(in) :: text
    type(json_object), allocatable :: next_objects(:)
    integer :: count

    count = size(objects)
    allocate(next_objects(count + 1))
    if (count > 0) next_objects(1:count) = objects
    next_objects(count + 1)%text = text
    call move_alloc(next_objects, objects)
  end subroutine append_object

  function load_json(path, api_path, token) result(json)
    character(len=*), intent(in) :: path, api_path, token
    character(:), allocatable :: json, temp_path, command

    if (len_trim(path) > 0) then
      json = read_file(path)
      return
    end if

    temp_path = make_temp_path()
    command = "curl -fsSL -H " // shell_quote("Authorization: Bearer " // token) // &
      " -H " // shell_quote("Accept: application/json") // &
      " -H " // shell_quote("Content-Type: application/json") // &
      " " // shell_quote(base_url // api_path) // " -o " // shell_quote(temp_path)
    call run_command(command, "MaiTea API request failed for " // api_path)
    json = read_file(temp_path)
    call execute_command_line("rm -f " // shell_quote(temp_path))
  end function load_json

  function make_temp_path() result(path)
    character(:), allocatable :: path
    character(:), allocatable :: tmpdir
    character(len=16) :: suffix
    real :: random_value

    tmpdir = env_value("TMPDIR")
    if (len_trim(tmpdir) == 0) tmpdir = "/tmp"
    call random_seed()
    call random_number(random_value)
    write(suffix, '(I0)') int(random_value * 100000000.0)
    path = trim(tmpdir) // "/maifetch_" // trim(suffix) // ".json"
  end function make_temp_path

  function shell_quote(text) result(quoted)
    character(len=*), intent(in) :: text
    character(:), allocatable :: quoted
    integer :: i

    quoted = "'"
    do i = 1, len_trim(text)
      if (text(i:i) == "'") then
        quoted = quoted // "'\''"
      else
        quoted = quoted // text(i:i)
      end if
    end do
    quoted = quoted // "'"
  end function shell_quote

  subroutine run_command(command, message)
    character(len=*), intent(in) :: command, message
    integer :: exit_status

    call execute_command_line(command, exitstat=exit_status)
    if (exit_status /= 0) call die(message)
  end subroutine run_command

  function ansi_fg(text, r, g, b, no_color) result(out)
    character(len=*), intent(in) :: text
    integer, intent(in) :: r, g, b
    logical, intent(in) :: no_color
    character(:), allocatable :: out

    if (no_color) then
      out = text
    else
      out = achar(27) // "[38;2;" // int_text(r) // ";" // int_text(g) // &
        ";" // int_text(b) // "m" // text // achar(27) // "[0m"
    end if
  end function ansi_fg

  function ansi_bg(text, r, g, b, no_color) result(out)
    character(len=*), intent(in) :: text
    integer, intent(in) :: r, g, b
    logical, intent(in) :: no_color
    character(:), allocatable :: out

    if (no_color) then
      out = text
    else
      out = achar(27) // "[38;2;255;255;255m" // achar(27) // &
        "[48;2;" // int_text(r) // ";" // int_text(g) // ";" // &
        int_text(b) // "m" // text // achar(27) // "[0m"
    end if
  end function ansi_bg

  function cyan(text, no_color) result(out)
    character(len=*), intent(in) :: text
    logical, intent(in) :: no_color
    character(:), allocatable :: out
    out = ansi_fg(text, 72, 184, 200, no_color)
  end function cyan

  function int_text(value) result(text)
    integer, intent(in) :: value
    character(:), allocatable :: text
    character(len=32) :: buffer
    write(buffer, '(I0)') value
    text = trim(buffer)
  end function int_text

  function rating_text(value) result(text)
    integer, intent(in) :: value
    character(:), allocatable :: text
    character(len=32) :: buffer
    write(buffer, '(F0.2)') real(value) / 100.0
    text = trim(buffer)
  end function rating_text

  function difficulty_label(value, no_color) result(label)
    character(len=*), intent(in) :: value
    logical, intent(in) :: no_color
    character(:), allocatable :: label

    select case (trim(value))
    case ("easy")
      label = ansi_bg("Easy", 69, 174, 255, no_color)
    case ("basic")
      label = ansi_bg("Basic", 111, 212, 61, no_color)
    case ("advanced")
      label = ansi_bg("Advanced", 248, 183, 9, no_color)
    case ("expert")
      label = ansi_bg("Expert", 255, 46, 66, no_color)
    case ("master")
      label = ansi_bg("Master", 171, 140, 233, no_color)
    case ("remaster", "re:master")
      label = ansi_bg("Re:Master", 207, 114, 237, no_color)
    case ("utage")
      label = ansi_bg("Utage", 255, 68, 1, no_color)
    case default
      label = trim(value)
    end select
  end function difficulty_label

  function rank_label(rank, no_color) result(label)
    character(len=*), intent(in) :: rank
    logical, intent(in) :: no_color
    character(:), allocatable :: label

    if (no_color) then
      label = trim(rank)
      return
    end if

    select case (trim(rank))
    case ("SSS+")
      label = ansi_fg("S", 255, 200, 54, .false.) // &
        ansi_fg("S", 225, 38, 165, .false.) // &
        ansi_fg("S", 73, 64, 233, .false.) // &
        ansi_fg("+", 21, 203, 148, .false.)
    case ("SSS")
      label = ansi_fg("S", 255, 200, 54, .false.) // &
        ansi_fg("S", 232, 39, 148, .false.) // &
        ansi_fg("S", 18, 195, 144, .false.)
    case ("SS+", "SS")
      label = ansi_bg(trim(rank), 143, 71, 33, .false.)
    case ("S+", "S")
      label = ansi_bg(trim(rank), 75, 82, 82, .false.)
    case ("AAA", "AA", "A")
      label = ansi_fg(trim(rank), 23, 163, 255, .false.)
    case default
      label = trim(rank)
    end select
  end function rank_label

  subroutine append_line(lines, text)
    type(line_item), allocatable, intent(inout) :: lines(:)
    character(len=*), intent(in) :: text
    type(line_item), allocatable :: next_lines(:)
    integer :: count

    count = size(lines)
    allocate(next_lines(count + 1))
    if (count > 0) next_lines(1:count) = lines
    next_lines(count + 1)%text = text
    call move_alloc(next_lines, lines)
  end subroutine append_line

  subroutine build_info_lines(profile, plays, score_count, no_color, lines)
    type(json_object), intent(in) :: profile
    type(json_object), intent(in) :: plays(:)
    integer, intent(in) :: score_count
    logical, intent(in) :: no_color
    type(line_item), allocatable, intent(inout) :: lines(:)
    character(:), allocatable :: name, song, difficulty, rank, combo
    character(:), allocatable :: score, achievement
    integer :: i, limit

    if (allocated(lines)) deallocate(lines)
    allocate(lines(0))
    name = json_string(profile%text, "name")
    if (len_trim(name) == 0) name = "MaiTea"

    call append_line(lines, cyan(name, no_color))
    call append_line(lines, repeat("-", len_trim(name)))
    call append_line(lines, cyan("ID", no_color) // ": " // &
      int_text(json_int(profile%text, "id", 0)))
    call append_line(lines, cyan("Rating", no_color) // ": " // &
      rating_text(json_int(profile%text, "rating", 0)) // " / " // &
      rating_text(json_int(profile%text, "rating_highest", 0)))
    call append_line(lines, cyan("Level", no_color) // ": " // &
      int_text(json_int(profile%text, "level", 0)))
    call append_line(lines, cyan("Total Credits", no_color) // ": " // &
      int_text(json_int(profile%text, "total", 0)))
    call append_line(lines, cyan("Recent Scores", no_color) // ":")

    limit = min(score_count, size(plays))
    do i = 1, limit
      song = json_string(plays(i)%text, "en")
      difficulty = json_string(plays(i)%text, "value")
      score = json_string(plays(i)%text, "score_formatted")
      achievement = json_string(plays(i)%text, "achievement_formatted")
      rank = json_string(plays(i)%text, "rank")
      combo = json_string(plays(i)%text, "full_combo_label")

      call append_line(lines, "  " // song // "  " // &
        difficulty_label(difficulty, no_color))
      call append_line(lines, trim("  " // score // " " // achievement // &
        "% " // rank_label(rank, no_color) // " " // combo))
      call append_line(lines, "")
    end do
  end subroutine build_info_lines

  function logo_line(icon_url, row, width, no_color) result(line)
    character(len=*), intent(in) :: icon_url
    integer, intent(in) :: row, width
    logical, intent(in) :: no_color
    character(:), allocatable :: line, raw
    character(len=*), parameter :: chars = " .:-=+*#%@"
    integer :: col, seed, idx, code

    seed = 0
    do idx = 1, len_trim(icon_url)
      code = iachar(icon_url(idx:idx))
      seed = seed + code
    end do

    raw = ""
    do col = 1, width
      idx = modulo(row * row + col * 3 + seed, len(chars)) + 1
      raw = raw // chars(idx:idx)
    end do

    line = ansi_fg(raw, 72, 184, 200, no_color)
  end function logo_line

  subroutine print_output(profile, plays, cfg)
    type(json_object), intent(in) :: profile
    type(json_object), intent(in) :: plays(:)
    type(config), intent(in) :: cfg
    type(line_item), allocatable :: lines(:)
    character(:), allocatable :: icon_url, logo, blank_logo
    integer :: i, max_lines, width

    allocate(lines(0))
    call build_info_lines(profile, plays, cfg%score_count, cfg%no_color, lines)
    if (cfg%logo_size <= 0) then
      do i = 1, size(lines)
        print '(A)', lines(i)%text
      end do
      return
    end if

    icon_url = json_string(profile%text, "png")
    width = max(cfg%logo_size * 2, 8)
    blank_logo = repeat(" ", width)
    max_lines = max(size(lines), cfg%logo_size)

    do i = 1, max_lines
      if (i <= cfg%logo_size) then
        logo = logo_line(icon_url, i, width, cfg%no_color)
      else
        logo = blank_logo
      end if

      if (i <= size(lines)) then
        print '(A)', logo // "  " // lines(i)%text
      else
        print '(A)', logo
      end if
    end do
  end subroutine print_output

  subroutine run()
    type(config) :: cfg
    character(:), allocatable :: profiles_json, plays_json
    type(json_object), allocatable :: profiles(:), plays(:)

    call load_config(cfg)
    profiles_json = load_json(cfg%profiles_fixture, "/api/v1/profiles", &
      cfg%access_token)
    plays_json = load_json(cfg%plays_fixture, "/api/v1/plays", &
      cfg%access_token)

    call parse_data_objects(profiles_json, profiles)
    call parse_data_objects(plays_json, plays)
    if (size(profiles) == 0) call die("No profiles found")

    call print_output(profiles(1), plays, cfg)
  end subroutine run
end module maifetch_app

program maifetch
  use maifetch_app
  implicit none
  call run()
end program maifetch
