require File.expand_path(File.join(File.dirname(__FILE__), '..','spec_helper'))

require 'rubygems'
require 'dep_selector/dependency_graph'
require 'dep_selector/dependency'
require 'dep_selector/objective_function'
require 'pp'

simple_cookbook_version_constraint =
  [{"key"=>["A", "1.0.0"], "value"=>{"B"=>"= 2.0.0"}},
   {"key"=>["A", "2.0.0"], "value"=>{"B"=>"= 1.0.0", "C"=>"= 1.0.0"}},
   {"key"=>["B", "1.0.0"], "value"=>{}},
   {"key"=>["B", "2.0.0"], "value"=>{}},
   {"key"=>["C", "1.0.0"], "value"=>{}}]

def setup_constraint(dep_graph, cset)
  cset.each do |cb_version|
    pv = dep_graph.package(cb_version["key"].first).add_version(cb_version["key"].last)
    cb_version['value'].each_pair do |dep_name, constraint|
      pv.dependencies << DepSelector::Dependency.new(dep_graph.package(dep_name), constraint)
    end
  end
  dep_graph.generate_gecode_constraints
end

def add_run_list(dep_graph, run_list)
  run_list.each do |run_list_item|
    pkg = dep_graph.package(run_list_item.first)
    constraint = run_list_item.last
    
    pkg_mv = pkg.gecode_model_var
    if constraint
      pkg_mv.must_be.in(pkg.densely_packed_versions[constraint])
    end
    dep_graph.branch_on(pkg_mv)
  end
end

def init_objective_function(dep_graph, run_list, current_versions)
  current_versions_densely_packed = current_versions.inject({}) do |acc, elt|
    acc[elt.first] = dep_graph.package(elt.first).densely_packed_versions["= #{elt.last}"].first
    acc
  end
  

# in our objective function
  explicit_densely_packed_dependencies = run_list.inject({}) do |acc, rli| 
    acc[rli.first] = dep_graph.package(rli.first).densely_packed_versions[rli.last] ; acc 
  end

  objective_function = DepSelector::ObjectiveFunction.new do |soln|
    # Note: We probably have to filter out the unnecessary dependencies
    # that are nonetheless bound here so that we're not unjustly
    # punishing the solution under consideration for appearing to change
    # packages that will actually just get removed.
    edit_distance = current_versions_densely_packed.inject(0) do |acc, curr_version|
      # TODO [cw,2010/11/21]: This edit distance only increases when a
      # package that is currently deployed is changed, not when a new
      # dependency is added. I think there is an argument to be made
      # that also including new packages is worthy of an edit distance
      # bump, since the interpretation can be that any difference in
      # code that is run (not just changing existing code) could be
      # considered "infrastructure instability". This needs to be
      # considered.
      pkg_name, curr_version_densely_packed = curr_version
      if soln.packages.has_key?(pkg_name)
        pkg = soln.package(pkg_name)
        putative_version = pkg.gecode_model_var.value
        puts "#{pkg_name} going from #{curr_version_densely_packed} to #{putative_version}"
        acc -= 1 unless putative_version == curr_version_densely_packed
      end
      acc
    end
  end
end

def dump_result(dep_graph, objective_function)
  objective_function.best_solution.keys.sort.each do |pkg_name|
    densely_packed_version = objective_function.best_solution[pkg_name]
    puts "#{pkg_name}: #{densely_packed_version} -> #{dep_graph.package(pkg_name).get_version_from_densely_packed_version(densely_packed_version)}"
  end
end

def verify_result(dep_graph, objective_function, expected_values)
  expected_values.each_pair do |pkg_name, version|
    densely_packed_version = objective_function.best_solution[pkg_name]
    computed_version = dep_graph.package(pkg_name).get_version_from_densely_packed_version(densely_packed_version).to_s
    computed_version.should == version
  end
end


describe DepSelector::DependencyGraph do
  it "can create a package named foo" do
    dep_graph = DepSelector::DependencyGraph.new
    pkg = dep_graph.package("A")
    pkg.name.should == "A"
  end
  
  it "can solve a simple system with one set of current versions" do
    dep_graph = DepSelector::DependencyGraph.new
    setup_constraint(dep_graph, simple_cookbook_version_constraint)
    run_list = [["A", nil]]
    add_run_list(dep_graph, run_list)
    current_versions = {"A" => "2.0.0", "B" => "1.0.0"}
    objective_function = init_objective_function(dep_graph, run_list, current_versions)
    dep_graph.each_solution do |soln|
      objective_function.consider(soln)
    end
    pp objective_function.best_solution
    dump_result(dep_graph, objective_function)
    verify_result(dep_graph, objective_function, {'A'=>'2.0.0', 'B'=>'1.0.0', 'C'=>'1.0.0'} )
  end

  it "can solve a simple system with another set of current versions" do
    dep_graph = DepSelector::DependencyGraph.new
    setup_constraint(dep_graph, simple_cookbook_version_constraint)
    run_list = [["A", nil]]
    add_run_list(dep_graph, run_list)
    current_versions = {"A" => "1.0.0", "B" => "2.0.0"}
    objective_function = init_objective_function(dep_graph, run_list, current_versions)
    dep_graph.each_solution do |soln|
      objective_function.consider(soln)
    end
    pp objective_function.best_solution
    dump_result(dep_graph, objective_function)
    verify_result(dep_graph, objective_function, {'A'=>'1.0.0', 'B'=>'2.0.0', 'C'=>'1.0.0'} )
  end


end