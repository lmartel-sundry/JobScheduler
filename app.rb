require 'sinatra'
require 'open-uri'
require 'csv'
require 'ap'
require 'relax4'
require 'set'

PREFS_COLUMN_BEGIN_INDEX = 1
PREFS_COLUMN_END_INDEX = -1

JOBS = ["PDC", "ADC", "Cook", "Weekly House Clean", "Weekly Kitchen Clean"]

class SchedulingTask
  def initialize(jobs, preferences)
    @jobs = jobs
    @preferences = preferences
    @node_indices = {}
  end

  def solve
    node_index_map = build_index_map()
    (start_nodes, end_nodes, costs) = link_jobs_to_people(node_index_map)
    demands = build_demands(node_index_map)
    capacities = start_nodes.map { 1 }

    @solution ||= Relax4.solve(demands: demands, start_nodes: start_nodes, end_nodes: end_nodes, costs: costs, capacities: capacities)
  end

  def build_index_map
    nodes = @preferences.keys + @jobs

    nodes.each_with_index.reduce(Hash.new) { |memo, (k, i)| memo[k] = (i + 1) ; memo }
  end

  def link_jobs_to_people(node_index_map)
    edges = @preferences.map do |person, preferences|
      preferences.each_with_index.map do |offset_job_index, preference|
        job_index = offset_job_index - 1
        node_of_job = node_index_map[@jobs[job_index]]
        node_of_person = node_index_map[person]

        [node_of_person, node_of_job, preference + 1]
      end
    end

    ap edges

    edges = edges.flatten(1)

    start_nodes = edges.map { |edge| edge[0] }
    end_nodes = edges.map { |edge| edge[1] }
    costs = edges.map { |edge| edge[2] }

    [start_nodes, end_nodes, costs]
  end

  def build_demands(node_index_map)
    job_set = Set.new(@jobs)
    node_index_map.map { |entity, node_index| job_set.include?(entity) ? 1 : -1 }
  end
end


get '/' do
    erb :index
end

post '/process' do
    # doc = open 'https://docs.google.com/spreadsheets/d/1H0cn1QIEDLGcmYhso00TP6Y_ACBH6ojxCURGhEX_Mqc/export?format=csv'
    doc = open params[:url].sub('htmlembed', 'export?format=csv')
    csv = CSV.new(doc, headers: :first_row)
    prefs = {}
    csv.read.each do |a| # Strip timestamp, hash name to prefs
        name = a[1]
        their_prefs = a.to_a[2..-1].map { |column, choice| JOBS.index(choice) + 1 }
        prefs[name] = their_prefs
    end

    solution = SchedulingTask.new(JOBS, prefs).solve
    solution
end