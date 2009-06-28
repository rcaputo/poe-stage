#!/usr/bin/env perl

use warnings;
use strict;

use XML::LibXML;
my $doc = XML::LibXML->createDocument();
my $main = $doc->createElement("main");
$doc->setDocumentElement($main);

{
	package Object;
	use Moose;

	my %elements;
	my %parent_elements;
	my %selves;

	my $node_id = 1;

	$elements{main} = $main;

	use Scalar::Util qw(weaken);

	has parent => (
		isa => 'Object',
		is => 'ro',
		weak_ref => 'yes',
	);

	has role => (
		isa => 'Str',
		is => 'ro',
	);

	sub BUILD {
		my ($self, $args) = @_;

		my $parent = $self->parent();

		unless (exists $elements{$parent}) {
			my $parent_element = $doc->createElement("object");
			$parent_element->setAttributeNode(
				$doc->createAttribute("role", "unknown")
			);
			$main->addChild($parent_element);

			$elements{$parent} = $parent_element;
			$parent_elements{$parent} = $elements{main};
		}

		my $self_element = $doc->createElement("object");
		$self_element->setAttributeNode(
			$doc->createAttribute("role", $self->role() || "unknown")
		);
		$self_element->setAttributeNode(
			$doc->createAttribute("class", ref($self))
		);

		$elements{$parent}->addChild($self_element);
		$elements{$self} = $self_element;
		$parent_elements{$self} = $elements{$parent};

		$selves{$$self_element} = $self;
		weaken $selves{$$self_element};
	}

	sub DEMOLISH {
		my $self = shift;

		return unless exists $elements{$self};
		return unless exists $parent_elements{$self};

		$parent_elements{$self}->removeChild($elements{$self});

		delete $selves{${$elements{$self}}};
		delete $elements{$self};
		delete $parent_elements{$self};
	}

	sub find {
		my ($class, $xpath) = @_;
		warn $main->findnodes($xpath);
		return(
			map { $selves{$$_} }
			$main->findnodes($xpath)
		);
	}
}

{
	package Cheat;
	use Moose;
}

{
	package ResolverWorker;
	use Moose;
	extends qw(Object);

	sub work {
		my $self = shift;
		print "worked: $self\n";
	}
}

{
	package Resolver;
	use Moose;
	extends qw(Object);
}

package main;

my $app = Object->new(
	parent => Cheat->new(), # to bootstrap
	role => "application",
);

# Simulate a DNS resolver pool.
my $resolver = Resolver->new(
	parent => $app,
	role => "resolver",
);

my @workers = map {
	ResolverWorker->new(
		parent => $resolver,
		role => "resolver_worker",
	)
} (1..5);

print $main->toString(), "\n";

# Find all resolver workers.
$_->work() foreach Object->find('//object[@role="resolver_worker"]');
