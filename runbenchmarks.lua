#!/bin/env lua

-- Configuration ---------------------------------------------------------------

-- 版本号与 `lua -v` / `luajit -v`、rpm 标签保持一致后改此处
local lua_ver = '5.4.6'
local luajit_ver = '2.1.20230821'
local pgo_root = './pgo_lua_root'
local pgo_ld = pgo_root .. '/usr/lib64'
local pgo_bin = pgo_root .. '/usr/bin/lua'
local pgo_luajit_root = './pgo_luajit_root'
local pgo_luajit_ld = pgo_luajit_root .. '/usr/lib64'
local pgo_luajit_bin = pgo_luajit_root .. '/usr/bin/luajit'

local binaries

local function binaries_for_preset(preset)
    local lua_cmd = 'env LD_LIBRARY_PATH=' .. pgo_ld .. ':${LD_LIBRARY_PATH} ' .. pgo_bin
    local luajit_pgo_cmd = 'env LD_LIBRARY_PATH=' .. pgo_luajit_ld .. ':${LD_LIBRARY_PATH} ' .. pgo_luajit_bin
    if preset == 'lua' then
        return {
            { 'lua-base-' .. lua_ver, 'lua' },
            { 'lua-perf-' .. lua_ver, lua_cmd },
        }
    elseif preset == 'luajit' then
        return {
            { 'luajit-base-' .. luajit_ver, 'luajit' },
            { 'luajit-perf-' .. luajit_ver, luajit_pgo_cmd },
        }
    elseif preset == 'combined' then
        -- 跑完后再折叠为 lua-base+luajit-base 与 lua-perf+luajit-perf 两列
        return {
            { 'lua-base-' .. lua_ver, 'lua' },
            { 'lua-perf-' .. lua_ver, lua_cmd },
            { 'luajit-base-' .. luajit_ver, 'luajit' },
            { 'luajit-perf-' .. luajit_ver, luajit_pgo_cmd },
        }
    end
    error('unknown preset: ' .. tostring(preset))
end

-- List of tests
local tests_root = './'
local tests = {
    { 'ack', 'ack.lua 3 10' },
    { 'fixpoint-fact', 'fixpoint-fact.lua 3000' },
    { 'heapsort', 'heapsort.lua 10 250000' },
    { 'mandelbrot', 'mandel.lua' },
    { 'juliaset', 'qt.lua' },
    { 'queen', 'queen.lua 12' },
    { 'sieve', 'sieve.lua 5000' }, -- Sieve of Eratosthenes
    { 'binary', 'binary-trees.lua 15' },
    { 'n-body', 'n-body.lua 1000000' },
    { 'fannkuch', 'fannkuch-redux.lua 10' },
    { 'fasta', 'fasta.lua 2500000' },
    { 'k-nucleotide', 'k-nucleotide.lua < fasta1000000.txt' },
    --{ 'regex-dna', 'regex-dna.lua < fasta1000000.txt' },
    { 'spectral-norm', 'spectral-norm.lua 1000' },
}

-- Command line arguments ------------------------------------------------------

local nruns = 3
local supress_errors = true 
local basename = 'results'
local normalize = false
local speedup = false
local plot = true

local preset = 'lua'

local usage = [[
usage: lua ]] .. arg[0] .. [[ [options]
options:
    --preset <name>  lua | luajit | combined | all (default = lua)
                     lua=仅 lua-base vs lua-perf；luajit=luajit-base vs luajit-perf；
                     combined=同一轮测四项后输出 (lua-base+luajit-base) vs (lua-perf+luajit-perf)；
                     all=一次跑四项，生成三组 txt/png：<output>_lua / _luajit / _combined
    --nruns <n>      number of times that each test is executed (default = 3)
    --no-supress     don't supress error messages from tests
    --output <name>  name of the benchmark output
    --normalize      normalize the result based on the first binary
    --speedup        compute the speedup based on the first binary
    --no-plot        don't create the plot with gnuplot
    --help           show this message
]]

local function parse_args()
    local function parse_error(msg)
        print('Error: ' .. msg .. '\n' .. usage)
        os.exit(1)
    end
    local function get_next_arg(i)
        if i + 1 > #arg then
            parse_error(arg[i] .. ' requires a value')
        end
        local v = arg[i + 1]
        arg[i + 1] = nil
        return v
    end
    for i = 1, #arg do
        if not arg[i] then goto continue end
        if arg[i] == '--nruns' then
            nruns = tonumber(get_next_arg(i))
            if not nruns or nruns < 1 then
                parse_error('nruns should be a number greater than 1')
            end
        elseif arg[i] == '--no-supress' then
            supress_errors = false
        elseif arg[i] == '--output' then
            basename = get_next_arg(i)
        elseif arg[i] == '--preset' then
            preset = get_next_arg(i)
        elseif arg[i] == '--normalize' then
            normalize = true
        elseif arg[i] == '--speedup' then
            speedup = true
        elseif arg[i] == '--no-plot' then
            plot = false
        elseif arg[i] == '--help' then
            print(usage)
            os.exit()
        else
            parse_error('invalid argument: ' .. arg[i])
        end
        ::continue::
    end
end

-- Implementation --------------------------------------------------------------

-- Run the command a single time and returns the time elapsed
local function measure(cmd)
    local time_cmd = '{ TIMEFORMAT=\'%3R\'; time ' ..  cmd ..
            ' > /dev/null; } 2>&1'
    local handle = io.popen(time_cmd)
    local result = handle:read("*a")
    local time_elapsed = tonumber(result)
    handle:close()
    if not time_elapsed then
        error('Invalid output for "' .. cmd .. '":\n' .. result)
    end
    return time_elapsed
end

-- Run the command $nruns and return the fastest time
local function benchmark(cmd)
    local min = 999
    io.write('running "' .. cmd .. '"... ')
    for _ = 1, nruns do
        local time = measure(cmd)
        min = math.min(min, time)
    end
    io.write('done\n')
    return min
end

-- Create a matrix with n rows
local function create_matrix(n)
    local m = {}
    for i = 1, n do
        m[i] = {}
    end
    return m
end

-- Measure the time for each binary and test
-- Return a matrix with the result (test x binary)
local function run_all()
    local results = create_matrix(#tests)
    for i, test in ipairs(tests) do
        local test_path = tests_root .. test[2]
        for j, binary in ipairs(binaries) do
            local cmd = binary[2] .. ' ' .. test_path
            local ok, msg = pcall(function()
                results[i][j] = benchmark(cmd)
            end)
            if not ok and not supress_errors then
                io.write('error:\n' .. msg .. '\n---\n')
            end
        end
    end
    return results 
end

-- Perform an operation for each value in the matrix
local function process_results(results, f)
    for _, line in ipairs(results) do
        local base = line[1]
        for i = 1, #binaries do
            line[i] = f(line[i], base)
        end
    end
end

-- Print info about the host computer
local function computer_info()
    os.execute([[
echo "Distro: "`cat /etc/*-release | head -1`
echo "Kernel: "`uname -r`
echo "CPU:    "`cat /proc/cpuinfo | grep 'model name' | tail -1 | \
                sed 's/model name.*:.//'`]])
end

-- Creates and saves the gnuplot data file
local function create_data_file(results)
    local data = 'test\t'
    for _, binary in ipairs(binaries) do
        data = data .. binary[1] .. '\t'
    end
    data = data .. '\n'
    for i, test in ipairs(tests) do
        data = data .. test[1] .. '\t'
        for j, _ in ipairs(binaries) do
            data = data .. results[i][j] .. '\t' 
        end
        data = data .. '\n'
    end
    io.open(basename .. '.txt', 'w'):write(data):close()
end

-- Generates the output image with gnuplot
local function generate_image()
    local ylabel
    if normalize then
        ylabel = 'Normalized time'
    elseif speedup then
        ylabel = 'Speedup'
    else
        ylabel = 'Elapsed time'
    end
    os.execute('gnuplot -e "datafile=\'' .. basename .. '.txt\'" ' ..
               '-e "outfile=\'' .. basename .. '.png\'" ' ..
               '-e "ylabel=\'' .. ylabel .. '\'" ' ..
               '-e "nbinaries=' .. #binaries .. '" plot.gpi')
end

local function setup()
    os.execute('luajit ' .. tests_root .. 'fasta.lua 1000000 > fasta1000000.txt')
end

local function teardown()
    os.execute('rm fasta1000000.txt')
end

-- 从四列原始结果中取出两列（1,2=lua，3,4=luajit）
local function slice_raw(m, a, b)
    local out = create_matrix(#m)
    for i = 1, #m do
        out[i][1] = m[i][a]
        out[i][2] = m[i][b]
    end
    return out
end

local function fold_lua_plus_luajit(m)
    local out = create_matrix(#m)
    for i = 1, #m do
        out[i][1] = m[i][1] + m[i][3]
        out[i][2] = m[i][2] + m[i][4]
    end
    return out
end

local function dup_process_emit(src, bin_row, base_out, build_f)
    binaries = bin_row
    local res = create_matrix(#src)
    for i = 1, #src do
        for j = 1, #bin_row do
            res[i][j] = src[i][j]
        end
    end
    process_results(res, build_f)
    basename = base_out
    create_data_file(res)
    if plot then generate_image() end
end

local function main()
    parse_args()
    local valid = { lua = true, luajit = true, combined = true, all = true }
    if not valid[preset] then
        print('Error: unknown --preset ' .. preset .. '\n' .. usage)
        os.exit(1)
    end

    local function build_f(v, base)
        if not v then
            return 0
        elseif not base then
            return v
        elseif speedup then
            return base / v
        elseif normalize then
            return v / base
        else
            return v
        end
    end

    local base_out = basename

    local function run_once_fourcol()
        computer_info()
        setup()
        binaries = binaries_for_preset('combined')
        local raw = run_all()
        teardown()
        return raw
    end

    if preset == 'all' then
        local raw = run_once_fourcol()
        dup_process_emit(slice_raw(raw, 1, 2), binaries_for_preset('lua'), base_out .. '_lua', build_f)
        dup_process_emit(slice_raw(raw, 3, 4), binaries_for_preset('luajit'), base_out .. '_luajit', build_f)
        dup_process_emit(fold_lua_plus_luajit(raw), {
            { 'lua-base+luajit-base', '' },
            { 'lua-perf+luajit-perf', '' },
        }, base_out .. '_combined', build_f)
        print('final done')
        return
    end

    computer_info()
    setup()

    local results
    if preset == 'combined' then
        binaries = binaries_for_preset('combined')
        results = run_all()
        teardown()
        results = fold_lua_plus_luajit(results)
        binaries = {
            { 'lua-base+luajit-base', '' },
            { 'lua-perf+luajit-perf', '' },
        }
    else
        binaries = binaries_for_preset(preset)
        results = run_all()
        teardown()
    end

    process_results(results, build_f)
    create_data_file(results)
    if plot then generate_image() end
    print('final done')
end

main()

