require 'sinatra'
require 'open-uri'
require 'csv'
require 'ap'
require 'relax4'
require 'set'
require 'json'

class SchedulingTask
  def initialize(jobs, demands, preferences)
    @jobs = jobs
    @preferences = preferences
    @demands = demands
    @node_indices = {}
  end

  def solve
    node_index_map = build_index_map()
    (start_nodes, end_nodes, costs) = link_jobs_to_people(node_index_map)
    demands = build_demands(node_index_map)
    capacities = start_nodes.map { 1 }

    @solution ||= Relax4.solve(demands: demands, start_nodes: start_nodes, end_nodes: end_nodes, costs: costs, capacities: capacities)

    map_solution_to_names(@solution, node_index_map, start_nodes, end_nodes)
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

    edges = edges.flatten(1)

    start_nodes = edges.map { |edge| edge[0] }
    end_nodes = edges.map { |edge| edge[1] }
    costs = edges.map { |edge| edge[2] }

    [start_nodes, end_nodes, costs]
  end

  def build_demands
    @demands
  end

  def map_solution_to_names(solution, node_index_map, start_nodes, end_nodes)
    inverted_map = node_index_map.reduce({}) { |memo, key, value| memo[value] = key }
    result = {}

    solution.each_with_index do |flow_value, edge_index|
      name_of_person = inverted_map[start_nodes[edge_index]]
      name_of_job = inverted_map[end_nodes[edge_index]]

      result[name_of_person] = name_of_job
    end

    return result
  end
end


get '/' do
    erb :index
end

post '/process' do
    # doc = open 'https://docs.google.com/spreadsheets/d/1H0cn1QIEDLGcmYhso00TP6Y_ACBH6ojxCURGhEX_Mqc/export?format=csv'
    tokens_by_line = params[:jobs].each_line.map { |line| line.chomp.split }
    jobs = tokens_by_line.map { |tokens| tokens[0..-2].join(' ') }
    demand = tokens_by_line.map(&:last).map(&:to_i)

    return "Incorrect input format" if jobs.length != demand.length
    return "Person requirements must be > 0!" if demands.filter { |d| d <= 0 }.size > 0

    doc = open params[:url].sub('htmlembed', 'export?format=csv')
    csv = CSV.new(doc, headers: :first_row)
    prefs = {}
    csv.read.each do |a| # Strip timestamp, hash name to prefs
        name = a[1]
        their_prefs = a.to_a[2..-1].map { |column, choice| jobs.index(choice) + 1 }
        prefs[name] = their_prefs
    end

    solution = SchedulingTask.new(JOBS, demands, prefs).solve
    solution
end
