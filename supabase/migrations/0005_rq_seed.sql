-- Roofing Quote Generator :: system defaults
--
-- These rows have contractor_id = null. They are the shared starting point
-- every contractor copies on sign-up, and the fallback for any line a
-- contractor has not overridden.

insert into public.rq_rate_items
  (contractor_id, code, category, label, description, unit, unit_cost, unit_price, sort_order)
select
  null, t.code, t.category, t.label, t.description, t.unit,
  t.unit_cost::numeric, t.unit_price::numeric, t.sort_order::int
from (values
  ('material_3tab',           'material',     '3-Tab Asphalt Shingle',              'Builder-grade strip shingle, 25 year warranty',        'sqft',      '4.20',  '95.00',  10),
  ('material_arch',           'material',     'Architectural Asphalt Shingle',      'Laminated shingle, 30+ year warranty',               'sqft',      '5.85',  '135.00', 20),
  ('material_metal',          'material',     'Standing Seam Metal Panel',          '24 gauge coated steel, 40+ year warranty',          'sqft',      '12.50', '485.00', 30),
  ('material_flat_membrane',  'material',     'TPO Low-Slope Membrane',            'Mechanically fastened or adhered single-ply',        'sqft',      '7.40',  '210.00', 40),
  ('material_tile',           'material',     'Concrete or Clay Tile',              'Long-life tile with underlayment and flashing',      'sqft',      '11.20', '425.00', 50),
  ('material_wood_shake',     'material',     'Cedar Wood Shake',                   'Natural cedar shake, 30+ year warranty',              'sqft',      '10.90', '385.00', 60),

  ('labor_install',           'labor',        'Roof Installation Labour',           'Tear-off, deck prep, dry-in, install and clean-up',  'sqft',      '0.00',  '145.00', 100),
  ('teardown_per_layer',      'teardown',     'Tear-Off, per layer',                'Shingle scraping, hauling to the pile and loading',  'sqft',      '0.00',  '65.00',  110),
  ('decking_repair',          'labor',        'Decking Replacement',                'Rip out, frame repair and install new plywood',      'sqft',      '62.00', '185.00', 120),

  ('underlayment_none',       'underlayment', 'No Underlayment',                    'Only valid on a dry-in overlay',                      'sqft',      '0.00',  '0.00',   130),
  ('underlayment_felt',       'underlayment', 'Felt Underlayment',                  '30 lb or 15 lb asphalt felt',                        'sqft',      '0.55',  '1.85',   140),
  ('underlayment_synthetic',  'underlayment', 'Synthetic Underlayment',             'Trizor or equivalent, cool roof rated',               'sqft',      '0.90',  '2.60',   150),
  ('underlayment_self_adhered','underlayment','Self-Adhered Underlayment',         'Peel and stick, ice and water rated',                'sqft',      '1.60',  '4.10',   160),

  ('ice_water_shield',        'accessory',    'Ice and Water Shield',               'Self-adhered membrane for eaves and valleys',         'sqft',      '1.05',  '3.40',   170),
  ('ventilation_none',        'accessory',    'No Attic Ventilation Work',          'Attic ventilation left as-is',                        'sqft',      '0.00',  '0.00',   180),
  ('ventilation_soffit_ridge', 'accessory',   'Ridge and Soffit Ventilation',       'Balanced intake and exhaust at code minimum',         'sqft',      '2.10',  '6.50',   190),
  ('ventilation_ridge_only',  'accessory',    'Ridge-Only Ventilation',            'Ridge vent with soffit baffles',                     'sqft',      '1.40',  '4.25',   200),
  ('ventilation_gable',       'accessory',    'Gable Ventilation',                 'Add gable vents to bring the attic up to code',       'sqft',      '1.65',  '5.00',   210),
  ('flashing_valley',         'accessory',    'Metal Valley Flashing',              'Woven or pre-formed metal valley on a 60 ft allowance','linear_ft', '2.35',  '7.75',   220),
  ('skylight_kit',            'accessory',    'Skylight Flashing Kit',              'Curb, step flashing and counter flashing',           'each',       '95.00', '385.00', 230),
  ('chimney_flashing',        'accessory',    'Chimney Flashing and Cricket',       'Step flashing, counter flashing and cricket',        'each',       '120.00','425.00', 240),
  ('gutter_new',              'accessory',    'New Gutter and Downspout',           'K-style or seamless aluminium, hung and tested',      'linear_ft',  '4.10',  '12.50', 250),
  ('gutter_remove',           'accessory',    'Gutter Removal',                     'Detach, haul and dispose of the existing gutter',    'linear_ft',  '1.30',  '4.75',   260),

  ('disposal_dump',           'disposal',     'Debris Haul-Away',                   'Truck and labour to remove all tear-off debris',      'sqft',      '0.95',  '3.20',   270),
  ('disposal_haulaway_bin',   'disposal',     'Dumpster Drop-off',                  'Container delivery, swap and final haul',            'each',       '240.00','650.00', 280),

  ('permit',                  'permit',       'Building Permit and Inspection',     'Permit fee, plan review and final inspection',       'each',       '165.00','425.00', 290),
  ('protection_tarps',        'protection',   'Property Protection and Cleanup',    'Tarps, plywood covers, magnets and final sweep',      'each',       '45.00', '145.00', 300)
) as t(code, category, label, description, unit, unit_cost, unit_price, sort_order)
where not exists (
  select 1 from public.rq_rate_items ri
  where ri.contractor_id is null and ri.code = t.code
);

insert into public.rq_questions
  (contractor_id, key, section, label, help_text, input_type, unit, options, required, affects_price, min_value, max_value, step_value, sort_order)
select
  null, t.key, t.section, t.label, t.help_text, t.input_type, t.unit,
  coalesce(t.options::jsonb, '[]'::jsonb),
  coalesce(t.required, false), coalesce(t.affects_price, true),
  t.min_value::numeric, t.max_value::numeric, t.step_value::numeric,
  t.sort_order::int
from (values
  -- ---- project ----------------------------------------------------------
  ('project_type', 'project', 'What kind of work do you need?', 'This decides whether we plan on removing the old roof first.', 'select', '', '["replacement","overlay","new_construction"]'::jsonb, true,  true, null, null, null, 10),
  ('roof_system',  'project', 'Which roofing material do you want?', 'Not sure? Architectural shingles are the usual choice for a full replacement.', 'select', '', '["arch","3tab","metal","flat_membrane","tile","wood_shake"]'::jsonb, true, true, null, null, null, 20),
  ('timeline',     'project', 'When do you want the work done?', '', 'select', '', '["asap","one_month","three_months","shopping"]'::jsonb, false, false, null, null, null, 30),

  -- ---- property ---------------------------------------------------------
  ('property_address', 'property', 'Where is the roof?', '', 'text', '', null, true, false, null, null, null, 10),
  ('property_city',    'property', 'City',   '', 'text', '', null, false, false, null, null, null, 20),
  ('property_state',   'property', 'State',  '', 'text', '', null, false, false, null, null, null, 30),
  ('property_zip',     'property', 'ZIP code', '', 'text', '', null, false, false, null, null, null, 40),
  ('stories',          'property', 'How many storeys is the building?', 'The storey the roof sits on counts as one.', 'number', 'storeys', null, true, true, '1', '4', '1', 50),
  ('footprint_sqft',   'property', 'Rough footprint of the building', 'The ground floor area in square feet, measured from outside.', 'number', 'sq ft', null, false, true, '200', '20000', '50', 60),
  ('roof_area_sqft',   'property', 'Measured roof area (optional)', 'If you already have a measurement, enter it. This overrides the footprint estimate and makes the quote far more accurate.', 'number', 'sq ft', null, false, true, '0', '60000', '50', 70),
  ('access_difficulty', 'property', 'How easy is it to get to the roof?', 'Driven access, steep banks and three-storey heights all slow the crew down.', 'select', '', '["easy","moderate","difficult"]'::jsonb, false, true, null, null, null, 80),

  -- ---- roof -------------------------------------------------------------
  ('pitch',              'roof', 'What is the roof pitch?', 'Rise over 12 inches of run. A 6 in 12 pitch is a fairly typical home roof.', 'number', 'in 12', null, true, true, '0', '16', '1', 10),
  ('existing_layers',    'roof', 'How many layers are on the roof now?', 'Look at the rafter ends or an eave from the ground. Two layers is the legal maximum in most places.', 'number', 'layers', null, false, true, '0', '4', '1', 20),
  ('decking_condition',  'roof', 'What is the condition of the decking?', 'From what you can see without lifting shingles. We verify on site before starting.', 'select', '', '["good","fair","poor","rotted"]'::jsonb, false, true, null, null, null, 30),
  ('valleys',            'roof', 'How many valleys does the roof have?', 'A valley is the inside crease where two roof slopes meet.', 'number', '', null, false, true, '0', '12', '1', 40),

  -- ---- upgrades ---------------------------------------------------------
  ('underlayment',         'upgrades', 'What underlayment do you want?', 'Underlayment is the waterproof layer between the deck and the shingles.', 'select', '', '["none","felt","synthetic","self_adhered"]'::jsonb, false, true, null, null, null, 10),
  ('ice_water_shield',     'upgrades', 'Ice and water shield', 'A self-adhered membrane on eaves and valleys. Worth it if you are in an ice dam area.', 'boolean', '', null, false, true, null, null, null, 20),
  ('ice_shield_coverage', 'upgrades', 'Ice and water shield coverage', 'As a percentage of the whole roof.', 'number', '%', null, false, true, '0', '100', '5', 30),
  ('ventilation',          'upgrades', 'What should we do about attic ventilation?', 'Poor attic heat is the number one cause of early shingle failure.', 'select', '', '["none","soffit_ridge","ridge_only","gable"]'::jsonb, false, true, null, null, null, 40),
  ('skylights',            'upgrades', 'How many skylights?', '', 'number', '', null, false, true, '0', '20', '1', 50),
  ('chimneys',             'upgrades', 'How many chimneys?', '', 'number', '', null, false, true, '0', '12', '1', 60),
  ('gutter_linear_ft',     'upgrades', 'Roughly how many feet of gutter?', 'The total run of gutter around the eaves.', 'number', 'linear ft', null, false, true, '0', '1200', '10', 70),

  -- ---- site -------------------------------------------------------------
  ('permit_needed',    'site', 'Do you need a building permit?', 'Most municipalities require one for a full replacement. We handle the filing.', 'boolean', '', null, false, true, null, null, null, 10),
  ('haul_away',        'site', 'How should the old roof be removed?', '', 'select', '', '["dumpster","truck","none"]'::jsonb, false, true, null, null, null, 20),
  ('protection_needed','site', 'Extra protection for landscaping and driveways?', 'Tarps, plywood covers and a magnet sweep of the yard.', 'boolean', '', null, false, true, null, null, null, 30),
  ('notes',            'site', 'Anything else we should know?', 'Pets in the yard, a difficult gate, water on site, damage we should look at.', 'text', '', null, false, false, null, null, null, 40)
) as t(key, section, label, help_text, input_type, unit, options, required, affects_price, min_value, max_value, step_value, sort_order)
where not exists (
  select 1 from public.rq_questions q
  where q.contractor_id is null and q.key = t.key
);