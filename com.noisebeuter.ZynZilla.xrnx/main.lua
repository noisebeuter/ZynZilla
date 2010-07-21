--[[============================================================================
main.lua
============================================================================]]--

-- locals

SAMPLE_BIT_DEPTH = 32
SAMPLE_FREQUENCY = 44100 --this should be set to the driver' sample rate
SAMPLE_CHANS = 1
  
OPERATORS = 6

WAVE_NONE = 1
WAVE_ARCCOSINE = WAVE_NONE + 1
WAVE_ARCSINE = WAVE_ARCCOSINE + 1
WAVE_CHEBYSHEV = WAVE_ARCSINE + 1
WAVE_CHIRP = WAVE_CHEBYSHEV + 1
WAVE_COSINE = WAVE_CHIRP + 1
WAVE_DIODE = WAVE_COSINE + 1
WAVE_GAUSS = WAVE_DIODE + 1
WAVE_NOISE = WAVE_GAUSS + 1
WAVE_PULSE = WAVE_NOISE + 1
WAVE_SAW = WAVE_PULSE + 1
WAVE_SINE =WAVE_SAW + 1
WAVE_SQUARE = WAVE_SINE + 1
WAVE_TANGENT = WAVE_SQUARE + 1
WAVE_TRIANGLE = WAVE_TANGENT + 1
WAVE_WAVETABLE = WAVE_TRIANGLE + 1
WAVE_NUMBER = WAVE_WAVETABLE

EPSILON = 1e-12
MINUSINFDB = -200.0

real_amplification = 1.0
int_note = 58 --A-4
int_wave_type_selected = WAVE_SINE
int_operator_selected = 1
int_frames = 0
real_cycles = 1

TWOPI = 2*math.pi
PI = math.pi
HALFPI = PI * 0.5
NOTE_BASE = math.pow(2,1/12)


--------------------------------------------------------------------------------
-- requires
--------------------------------------------------------------------------------

require "gui"
require "operators"


--------------------------------------------------------------------------------
-- globals
--------------------------------------------------------------------------------

notifiers = {}

array_string_operators = 
{
  "-NONE-",
  "Arc Cosine", 
  "Arc Sine", 
  "Chebyshev",
  "Chirp",
  "Cosine", 
  "Diode",
  "Gauss",
  "Noise", 
  "Pulse", 
  "Saw", 
  "Sine", 
  "Square", 
  "Tangent",
  "Triangle", 
  "Wave"
}
  
array_function_operators = 
{
  none,
  arccosine,
  arcsine,
  chebyshev,
  chirp,
  cosine,
  diode,
  gauss,
  noise,
  pulse,
  saw,
  sine,
  square,
  tangent,
  triangle,
  wave
}
  
array_real_amplitudes = {}
array_variant_parameters = {}
array_instrument_number = {} -- to be used with WAVE operator
array_sample_number = {} -- to be used with WAVE operator
array_boolean_inverts = {}
array_int_modulators = {}
array_real_harmonics_amplitudes = {}
array_real_phase_shift = {}
array_waves = {}
array_minislider_harmonics = {}
array_minislider_phase_shift = {}

int_harmonics_per_wave = 256
int_harmonics_per_tab = 64
int_harmonics_tab = 1


--------------------------------------------------------------------------------
-- menu registration
--------------------------------------------------------------------------------

renoise.tool():add_menu_entry {
  name = "Sample Editor:ZynZilla...",
  invoke = function() show_dialog() end
}


--------------------------------------------------------------------------------
-- helper functions
--------------------------------------------------------------------------------

function note_to_frequency(int_note)
  return 440 * math.pow(NOTE_BASE,(int_note-58))
end

--------------------------------------------------------------------------------

function convert_linear_to_db(real_value)
  if (real_value > EPSILON) then
    return math.log10(real_value) * 20.0
  else
    return MINUSINFDB
  end
end


--------------------------------------------------------------------------------

function convert_db_to_linear(real_value)
  if (real_value > MINUSINFDB) then
    return math.pow(10.0, real_value * 0.05)
  else
    return 0.0
  end
end


--------------------------------------------------------------------------------
-- data processing
--------------------------------------------------------------------------------

function wave_is_set(int_wave)

  return
    array_waves[int_wave] and 
    array_real_amplitudes[int_wave] and 
    (array_variant_parameters[int_wave] ~= nil or 
     array_instrument_number[int_wave]) and 
    array_waves[int_wave] ~= WAVE_NONE
    
end


--------------------------------------------------------------------------------

function initialize_wave(int_wave_number)
  array_waves[int_wave_number] = WAVE_NONE
  array_real_amplitudes[int_wave_number] = 1
  array_variant_parameters[int_wave_number] = 0.5
  array_boolean_inverts[int_wave_number] = false
  array_real_harmonics_amplitudes[int_wave_number] = {}
  array_real_phase_shift[int_wave_number] = {}
  array_int_modulators[int_wave_number] = 0
  array_instrument_number[int_wave_number] = 0
  array_sample_number[int_wave_number] = 0
end


--------------------------------------------------------------------------------

function is_modulated(int_operator)

  local int_count
  local int_mod = 0
  local array_int_return = {}
  for int_count = 1,OPERATORS do
    if array_int_modulators[int_count] == int_operator then
      int_mod = int_mod + 1
      array_int_return[int_mod] = int_count
    end
  end
  
  return array_int_return, int_mod
  
end


--------------------------------------------------------------------------------

function is_modulator(int_operator)

  return array_int_modulators[int_operator] and 
    array_int_modulators[int_operator] > 0

end


--------------------------------------------------------------------------------

function operate(int_wave,real_x,real_amplitude_factor,array_int_harmonic_indexes)

  local real_amplitude = array_real_amplitudes[int_wave]
  local variant_parameter = array_variant_parameters[int_wave]

  local real_operator_value = 0
  if array_waves[int_wave] then  
    local harmonics = array_real_harmonics_amplitudes[int_wave]

    for _, int_harmonic in ipairs(array_int_harmonic_indexes) do
      local real_phase_shift = array_real_phase_shift[int_wave][int_harmonic]
      local real_phase = real_x + real_phase_shift
      local real_harmonic = array_real_harmonics_amplitudes[int_wave][int_harmonic]

      real_phase = math.fmod(real_phase * int_harmonic,1.0) 

      real_operator_value = real_operator_value +
        array_function_operators[array_waves[int_wave]](
          real_amplitude * real_harmonic * real_amplitude_factor,
          variant_parameter,
          real_phase
        )

    end
  else
    real_operator_value = 0
  end

  if array_boolean_inverts[int_wave] then 
    real_operator_value = -1 * real_operator_value 
  end
  
  return real_operator_value
  
end


--------------------------------------------------------------------------------

function process_data(real_amplification,real_x)

  local int_waves = table.getn(array_waves)
  local int_wave
  local int_valid_waves = 0
  local real_frame_value = 0
  
  for int_wave = 1, int_waves do
  
    if 
      array_waves[int_wave] == WAVE_WAVETABLE and 
      array_instrument_number[int_wave] > 0 and 
      array_sample_number[int_wave] > 0 
    then
      -- for WAVE mode, get the latest sample buffer
      array_variant_parameters[int_wave] = 
      renoise.song().instruments[array_instrument_number[int_wave]]
      .samples[array_sample_number[int_wave]]
        .sample_buffer
    end

    -- compute amplitude factor and find indexes of harmonic amplitude
    -- harmonics for this wave
    local harmonics = array_real_harmonics_amplitudes[int_wave]

    local real_sum_harmonic_amplitudes = 0.0

    local array_int_harmonic_indexes = {}

    local real_amplitude = array_real_amplitudes[int_wave]

    for int_harmonic = 1, int_harmonics_per_wave do
      local real_harmonic_amplitude

      if harmonics[int_harmonic] then
        real_harmonic_amplitude = harmonics[int_harmonic]
        if real_harmonic_amplitude < 0 then
          real_harmonic_amplitude = real_harmonic_amplitude * -1
        end
      else
        real_harmonic_amplitude = 0.0
      end

      real_sum_harmonic_amplitudes =
        real_sum_harmonic_amplitudes + (real_harmonic_amplitude * real_amplitude)

      if real_harmonic_amplitude ~= 0.0 then
        table.insert(array_int_harmonic_indexes, int_harmonic)
        if array_real_phase_shift[int_wave][int_harmonic] == nil then
          array_real_phase_shift[int_wave][int_harmonic] = 0
        end
      end
    end

    local real_amplitude_factor = real_amplitude / real_sum_harmonic_amplitudes
  
  
    if 
      wave_is_set(int_wave) and 
      array_waves[int_wave] > 0 and 
      is_modulator(int_wave) == false 
    then
    
      local real_modulator = 0.0
      local array_modulators, int_modulators = is_modulated(int_wave)
    
      if int_modulators > 0 then
        -- modulate the amplitude of the current operator by the 
        -- operators which are assigned to it 
        local int_modulator
        local array_real_modulators = {}
        local int_count = 0
        for int_modulator = 1, int_modulators do
   
          int_count = int_count + 1
          local int_wave = array_modulators[int_modulator]
          array_real_modulators[int_count] = 
        array_real_amplitudes[int_wave] * operate(int_wave,real_x,real_amplitude_factor,array_int_harmonic_indexes)
          
        end

        for int_modulator = 1, int_modulators do
          real_modulator = real_modulator + 
            array_real_modulators[int_modulator]
        end
        
        real_modulator = real_modulator / int_modulators

      end
    
      local real_operator_value = operate(int_wave,real_x,real_amplitude_factor,array_int_harmonic_indexes)
        
      real_frame_value = real_frame_value + 
      real_operator_value * (1 + real_modulator)
        
      int_valid_waves = int_valid_waves + 1
            
    end
  
  end
  
  if int_valid_waves > 0 then
    real_frame_value = real_amplification * 
    real_frame_value / int_valid_waves
  end
  
  return real_frame_value, int_valid_waves

end


--------------------------------------------------------------------------------

function generate()

  local instrument = renoise.song().selected_instrument
  local int_sample_index = renoise.song().selected_sample_index
  local int_samples = table.getn(instrument.samples)
  
  local buffer_new,sample_new
  
  if(int_samples == 0) then 
    sample_new = instrument:insert_sample_at(int_sample_index) 
  else
    sample_new = renoise.song().selected_sample
  end
  
  buffer_new = sample_new.sample_buffer
  
  if int_frames == 0 then 
    int_frames = SAMPLE_FREQUENCY / note_to_frequency(int_note) 
  end
  
  --create the new sample
  if 
    int_frames > 0 and 
    not buffer_new:create_sample_data(
      SAMPLE_FREQUENCY, 
      SAMPLE_BIT_DEPTH, 
      SAMPLE_CHANS, 
      real_cycles*int_frames
    )
  then
    renoise.app():show_error("Error during sample creation!")
    renoise.song():undo()
    return
  end

  local int_chan,int_frame,real_frame_value,int_valid_waves
  for int_chan = 1, SAMPLE_CHANS do
    for int_frame = 1, buffer_new.number_of_frames do
      real_frame_value, int_valid_waves = 
      process_data(real_amplification,int_frame/int_frames)
      buffer_new:set_sample_data(int_chan,int_frame,real_frame_value)
    end
  end
  
  buffer_new:finalize_sample_data_changes()
  
  sample_new.base_note = int_note-1
  instrument.split_map[int_note] = int_sample_index

end

